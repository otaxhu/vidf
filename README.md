# vidf - Version Manager for ESP-IDF

[`vidf`](/vidf) is a CLI proof of concept (PoC) for a lightweight version manager for the ESP-IDF (Espressif IoT Development Framework) ecosystem.

This repository serves as a prototype to validate a single-script hybrid design (acting as both an installer and a version/environment manager) and to test the ergonomics of the `vidf` command.

## Motivations

While official tools like [`esp-im-ui`](https://github.com/espressif/esp-im-ui) provide comprehensive features and visual interfaces —which remains the **highly recommended** and excellent solution for **Windows-based** enterprise environments— `vidf` aims to offer a lightweight, CLI-focused alternative. The goal is to build a minimal, POSIX-compliant script tailored exclusively for developers who prefer pure scripts and automated workflows over heavy graphical managers.

Another reason is that I wanted to explore the architecture and design of the [`nvm`](https://github.com/nvm-sh/nvm) project, and I wanted to recreate it targetting on another platform, such as ESP-IDF.

## License

VIDF project is published under the terms of the GNU General Public License v3.0 or later versions.

```
Copyright (c) 2026 Oscar Pernia

vidf is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
```
