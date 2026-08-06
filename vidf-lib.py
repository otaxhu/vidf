# Copyright (C) 2026 Oscar Pernia
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

import argparse
import asyncio
import functools
import os
import pathlib
import re
import signal
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from http import HTTPStatus
from typing import List, Optional, TextIO, Self
from urllib.parse import urlsplit, unquote as urlunquote

import aiofiles
import httpx2
import rich.markup
import rich.highlighter
import rich.theme
from rich.text import Text
from rich.console import Console
from rich.progress import (
    BarColumn,
    Progress,
    SpinnerColumn,
    TextColumn,
    TaskID,
    TimeRemainingColumn,
    TransferSpeedColumn,
)

TimeRemainingColumn = functools.partial(
    TimeRemainingColumn, compact=True, elapsed_when_finished=True
)

CHECKMARK_CHAR = Text("\u2714", style="green bold")
CROSSMARK_CHAR = Text("\u2718", style="red bold")

err_console = Console(stderr=True)
error_console = Console(stderr=True, style="red")

# Is used in the highlighters
cmd_theme = rich.theme.Theme({"cmd": "bold"})


def parse_http_date(date_str: str) -> Optional[float]:
    try:
        dt = datetime.strptime(date_str, "%a, %d %b %Y %H:%M:%S GMT")
        return dt.replace(tzinfo=timezone.utc).timestamp()
    except ValueError, TypeError:
        return None


def format_http_date(timestamp: float) -> str:
    dt = datetime.fromtimestamp(timestamp, tz=timezone.utc)
    return dt.strftime("%a, %d %b %Y %H:%M:%S GMT")


@dataclass
class DownloadTask:
    """
    Model class that holds the rich's TaskID together with the
    download url it belongs to
    """

    task_id: TaskID
    url: str
    filename: str

    @classmethod
    def from_url(cls, task_id: TaskID, url: str) -> Self:
        parsed_url = urlsplit(url)
        filename = urlunquote(pathlib.Path(parsed_url.path).name)
        return cls(task_id=task_id, url=url, filename=filename)


async def run_download_file(urls: List[str], out_dir: str) -> int:
    urls = list(set(urls))

    os.makedirs(out_dir, exist_ok=True, mode=0o755)
    exit_code = 0

    spinner_col = SpinnerColumn(spinner_name="dots", finished_text=CROSSMARK_CHAR)

    with Progress(
        spinner_col,
        TextColumn("{task.description}"),
        BarColumn(),
        TimeRemainingColumn(),
        TransferSpeedColumn(),
        TextColumn("{task.fields[info]}", style="dim"),
        console=err_console,
    ) as progress:
        download_tasks_list: list[DownloadTask] = []

        for url in urls:
            download_tasks_list.append(
                DownloadTask.from_url(
                    progress.add_task(
                        f"Downloading [bold]{rich.markup.escape(url)}[/]",
                        total=None,
                        start=False,
                        # Extra fields
                        info="",
                    ),
                    url,
                )
            )

        async with httpx2.AsyncClient(
            http2=True,
            follow_redirects=True,
        ) as client:

            async def download_worker(download_task: DownloadTask):
                task_id = download_task.task_id
                filename = download_task.filename
                url = download_task.url

                nonlocal exit_code

                outpath = os.path.join(out_dir, filename)
                tmppath = f"{outpath}.tmp"

                headers = {}
                local_mtime: Optional[float] = None

                if os.path.exists(outpath) and os.path.isfile(outpath):
                    local_mtime = os.path.getmtime(outpath)
                    headers["If-Modified-Since"] = format_http_date(local_mtime)

                try:
                    async with client.stream("GET", url, headers=headers) as res:
                        content_len: Optional[int] = (
                            None  # In order to not render progress bar if Content-Length header is missing
                        )
                        try:
                            content_len = int(res.headers["Content-Length"])
                        except KeyError, ValueError:
                            pass

                        progress.update(task_id, total=content_len)
                        progress.start_task(task_id)

                        remote_mtime: Optional[float] = None
                        try:
                            remote_mtime = parse_http_date(res.headers["Last-Modified"])
                        except KeyError:
                            pass

                        if res.status_code == HTTPStatus.NOT_MODIFIED or (
                            res.is_success  # Simulate HTTP 304 response code
                            and local_mtime
                            and remote_mtime
                            and remote_mtime <= local_mtime
                        ):
                            spinner_col.finished_text = CHECKMARK_CHAR
                            progress.update(
                                task_id, total=1, advance=1, info="(Cache hit)"
                            )
                            return

                        res.raise_for_status()

                        # Warn about response codes other than 200
                        if res.status_code != HTTPStatus.OK:
                            progress.update(
                                task_id,
                                info=f"([yellow]Got HTTP {res.status_code} code, expected 200[/], attempting to download)",
                            )

                        async with aiofiles.open(tmppath, "wb") as temp:
                            async for bb in res.aiter_bytes():
                                await temp.write(bb)
                                progress.update(task_id, advance=len(bb))

                        spinner_col.finished_text = CHECKMARK_CHAR
                        progress.update(task_id, total=1, completed=1)
                        os.replace(tmppath, outpath)

                except BaseException as e:
                    exit_code = 1
                    if isinstance(e, httpx2.HTTPStatusError):
                        progress.update(
                            task_id,
                            info=f"([red]HTTP {e.response.status_code} error[/])",
                        )
                    elif not isinstance(e, asyncio.CancelledError):
                        progress.update(
                            task_id,
                            info=f"([red]Got error: {rich.markup.escape(str(e))}[/])",
                        )
                    # Re-raise after identifying the download that failed
                    raise

            try:
                async with asyncio.TaskGroup() as tg:
                    for dt in download_tasks_list:
                        tg.create_task(download_worker(dt))
            except* httpx2.RequestError:
                # TODO: Network related errors
                pass

    return exit_code


async def run_progress_command(
    cmd: List[str], message: str, on_success: str, on_fail: str
) -> int:
    if len(cmd) == 0:
        error_console.print("You must specify at least 1 argument")
        return 2

    on_success = on_success or ""
    on_success = (
        rich.markup.escape(on_success)
        or f"{rich.markup.escape(' '.join(cmd))} completed succesfully"
    )
    on_fail = on_fail or ""
    on_fail = (
        rich.markup.escape(on_fail) or f"{rich.markup.escape(' '.join(cmd))} failed"
    )

    try:
        # Get the tty device from stdin
        tty_console = Console(
            file=open(os.ttyname(sys.stdin.fileno()), mode="w"),
            # Highlights command name dynamically
            theme=cmd_theme,
        )
    except OSError:
        # There is no connected tty, don't print any progress, execute the command directly
        # Optimization: Calling execve syscall in order to reuse the same process
        try:
            os.execvp(cmd[0], cmd)
        except FileNotFoundError:
            error_console.print(
                "Command not found:", Text(f"{cmd[0]}", style="red bold")
            )
            return 127

    stdout_is_tty = sys.stdout.isatty()
    stderr_is_tty = sys.stderr.isatty()

    spinner_col = SpinnerColumn(spinner_name="dots", finished_text=CROSSMARK_CHAR)

    highlighter = rich.highlighter.RegexHighlighter()
    highlighter.highlights = [rf"(^|\s+)(?P<cmd>{re.escape(cmd[0])})(\s|$)"]
    text_col = TextColumn("{task.description}", highlighter=highlighter)

    exit_code = 1
    proc = None

    with Progress(
        spinner_col,
        text_col,
        console=tty_console,
    ) as progress:
        task_id = progress.add_task(rich.markup.escape(message), total=None)
        try:
            proc = await asyncio.subprocess.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE if stdout_is_tty else None,
                stderr=asyncio.subprocess.PIPE if stderr_is_tty else None,
            )

            async def stream_pipe(file: TextIO, stream: asyncio.StreamReader):
                while buf := await stream.read(0x10000):
                    print(buf.decode(errors="replace"), file=file, end="")

            if stdout_is_tty and stderr_is_tty:
                await asyncio.gather(
                    stream_pipe(sys.stdout, proc.stdout),
                    stream_pipe(sys.stderr, proc.stderr),
                )
            elif stdout_is_tty:
                await stream_pipe(sys.stdout, proc.stdout)
            elif stderr_is_tty:
                await stream_pipe(sys.stderr, proc.stderr)

        except FileNotFoundError:
            exit_code = 127
        finally:
            if proc is not None:
                await proc.wait()
                if exit_code != 127:
                    exit_code = proc.returncode

        if exit_code == 127:
            progress.update(
                task_id, description=f"Command not found: {rich.markup.escape(cmd[0])}"
            )
        elif exit_code != 0:
            progress.update(task_id, description=on_fail)

        if exit_code != 0:
            text_col.style = "red"
        else:
            spinner_col.finished_text = CHECKMARK_CHAR
            text_col.style = "green"
            progress.update(task_id, description=on_success)

        progress.update(task_id, total=1, completed=1)

    return exit_code


async def handle_shutdown():
    loop = asyncio.get_running_loop()
    tasks = [t for t in asyncio.all_tasks(loop) if t != asyncio.current_task(loop)]
    for t in tasks:
        t.cancel()


async def main():
    loop = asyncio.get_running_loop()
    for s in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(s, lambda: asyncio.create_task(handle_shutdown()))

    parser = argparse.ArgumentParser(
        description="CLI library utilities and helper functions for vidf project",
    )

    subparser = parser.add_subparsers(
        required=True, dest="subcommand", help="Available utilities"
    )

    progress_parser = subparser.add_parser(
        "progress-command", help="Runs a command with an spinner"
    )
    progress_parser.add_argument(
        "message", type=str, help="Message to show alongside the spinner"
    )
    progress_parser.add_argument(
        "--on-success",
        type=str,
        help="Message to show on command success",
    )
    progress_parser.add_argument(
        "--on-fail",
        type=str,
        help="Message to show on command failure",
    )
    progress_parser.add_argument(
        "cmd", nargs=argparse.REMAINDER, help="Command arguments to execute"
    )

    dl_parser = subparser.add_parser(
        "download-file",
        help="Download files with progress bars",
        epilog=" ".join(
            [
                "It handles cache validation by:",
                "Sending to the server the stored file's mtime, if exists, and checking",
                "for HTTP 304 Not Modified responses. It as well simulates an HTTP 304 Not Modified",
                'response if the "Last-Modified" HTTP header is older than the current found on system.',
            ]
        ),
    )
    dl_parser.add_argument(
        "--out-dir",
        type=str,
        required=True,
        help="Output directory to store the downloaded files",
    )
    dl_parser.add_argument(
        "url",
        type=str,
        nargs=argparse.ONE_OR_MORE,
        help="HTTP URLs to download",
    )

    args = parser.parse_args()

    match args.subcommand:
        case "progress-command":
            sys.exit(
                await run_progress_command(
                    args.cmd, args.message, args.on_success, args.on_fail
                )
            )
        case "download-file":
            sys.exit(await run_download_file(args.url, args.out_dir))


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except asyncio.CancelledError:
        error_console.print("Operation aborted")
        sys.exit(1)
