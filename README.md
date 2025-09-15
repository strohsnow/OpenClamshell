# OpenClamshell

A macOS utility to enable clamshell mode with the MacBook lid open. This allows you to use your external monitor as the main display without having to close your MacBook.

## The Problem

Normally, to use a MacBook in "clamshell mode" with external monitors, you need to close the lid. This can be inconvenient if you want to use the MacBook's keyboard or trackpad, or if you prefer to have the lid open for better cooling. When you connect an external monitor with the lid open, macOS extends the desktop to both the built-in display and the external one.

## The Solution

`OpenClamshell` solves this by automatically dimming the built-in display to zero brightness and mirroring the external display to the built-in one when an external display is connected. This effectively makes your external monitor the only active display, achieving a "lid-open clamshell" experience. When you disconnect the external display, your built-in display's brightness is restored.

## Installation

1.  **Clone the repository:**
    ```sh
    git clone https://github.com/strohsnow/OpenClamshell.git
    cd OpenClamshell
    ```

2.  **Build the application:**
    ```sh
    swiftc -O -o OpenClamshell OpenClamshell.swift -framework Foundation -framework CoreGraphics -framework AppKit
    ```
    This will compile the Swift code and create an executable named `OpenClamshell`.

3.  **Install the service:**
    ```sh
    ./OpenClamshell --install
    ```
    This will copy the `OpenClamshell` executable to `/usr/local/bin` and set up the `launchd` service.

    > **Note:**
    > You may need to run the install command with `sudo` if you get a permission error:
    > ```
    > sudo ./OpenClamshell --install
    > ```

## Usage

The application runs in the background. The command-line interface is used for installation and uninstallation.

*   **Install:**
    ```sh
    ./OpenClamshell --install
    ```
    Sets up and starts the background service.

*   **Uninstall:**
    ```sh
    ./OpenClamshell --uninstall
    ```
    Stops the service and removes all installed files.

## Compatibility

This utility has been tested on macOS 26. It may work on other versions, but compatibility is not guaranteed.

## How It Works

`OpenClamshell` is a lightweight Swift application that listens for screen parameter changes.

1.  **Display Detection:** When it detects a change in connected displays, it checks for the presence of both a built-in display and an external display.

2.  **Brightness Control:**
    *   When an external display is connected, it saves the current brightness of the built-in display and then sets the brightness to zero.
    *   When the external display is disconnected, it restores the saved brightness to the built-in display.

3.  **Display Mirroring:** To prevent the system from using the dimmed built-in display as an active desktop, it programmatically configures display mirroring, making the external display the mirror source for the built-in one.

4.  **Launchd Service:** The `--install` command creates a `launchd` property list (`.plist`) file in `~/Library/LaunchAgents/`. This ensures that the `OpenClamshell` application is automatically launched every time you log in.
