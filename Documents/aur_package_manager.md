# AUR Package Manager Script

<u>**Note: Only for git Repositorys**</u>

This script automates the process of creating and updating packages on the Arch User Repository (AUR). It handles dependencies, SSH key setup for AUR, package validation, PKGBUILD generation, and Git operations for pushing changes to the AUR.

## Features

*   **Dependency Check**: Ensures `git`, `curl`, `makepkg`, and `namcap` are installed.
*   **AUR SSH Setup**: Guides you through generating an SSH key (if needed) and configuring your SSH client to connect to AUR. It also prompts you to add your public key to your AUR account.
*   **Package Name and Version Validation**: Basic validation for package names and versions.
*   **New Package Creation**:
    *   Prompts for package name, version, description, Git URL, license, dependencies, and architecture.
    *   Validates the provided Git URL.
    *   Clones the AUR repository for the new package.
    *   **Crucially, it checks for a `setup.sh` script within the source repository (either in the root or one level deep) which it expects to use as the main executable for your package.**
    *   Generates a `PKGBUILD` file based on your input.
    *   Generates the `.SRCINFO` file.
    *   Performs a local test build and installation using `makepkg`.
    *   Cleans up build files.
    *   Manages Git operations (add, commit, push) to the AUR.
*   **Package Update**:
    *   Lists existing AUR packages in your `~/aur-packages` directory.
    *   Allows you to select a package to update.
    *   Prompts for a new version number.
    *   Automatically increments `pkgrel` if the version remains the same, or resets it to `1` for a new version.
    *   Updates `PKGBUILD` and `.SRCINFO`.
    *   Performs a local test build and installation.
    *   Manages Git operations to push updates to the AUR.
*   **Interactive Prompts**: Guides the user through each step with clear prompts.

## Prerequisites

Before running this script, ensure you have the following installed:

*   `git`
*   `curl`
*   `makepkg` (part of `pacman` and base-devel group)
*   `namcap` (can be installed from the Arch repositories)

You should also have an Arch Linux system configured to interact with the AUR.

## Usage

1.  **Run the script**:
    ```bash
    ./Start_aur_package_manager.sh
    ```

2.  **Follow the prompts**:
    *   You will be asked if you want to `(c)reate` or `(u)pdate` an AUR package.
    *   **For creating a new package**:
        *   Provide details like package name, version, description, Git URL of your source repository, license, dependencies (space-separated), and architecture.
        *   The script will check if a `setup.sh` file exists in your source repository's root or one level deep. **This `setup.sh` is crucial as the script expects it to be your main executable.**
        *   It will guide you through SSH key setup if needed.
        *   Review the generated `PKGBUILD` and `.SRCINFO` before confirming the push to AUR.
    *   **For updating an existing package**:
        *   The script will list available packages from `~/aur-packages`. Select the one you wish to update.
        *   Provide the new version number.
        *   Review the updated `PKGBUILD` and `.SRCINFO` before confirming the push to AUR.

## Step-by-Step Guide: Creating an AUR Package

1. **Prepare Your Project**
   - Ensure your project is hosted in a public Git repository (e.g., GitHub, GitLab).
   - The project should have a clear main executable or install script (commonly named `setup.sh` for shell scripts, or a compiled binary for other languages).

2. **Set Up Your Arch System**
   - Install required tools:
     ```bash
     sudo pacman -S --needed git base-devel namcap
     ```
   - Create an account on the [AUR website](https://aur.archlinux.org/).

3. **Set Up SSH for AUR**
   - Generate an SSH key if you don’t have one:
     ```bash
     ssh-keygen -t ed25519 -C "your_email@example.com"
     ```
   - Add your public key (`~/.ssh/id_ed25519.pub`) to your AUR account (in your account settings on the AUR website).
   - Test your SSH connection:
     ```bash
     ssh aur@aur.archlinux.org
     ```

4. **Create a Local Directory for AUR Packages**
   - It’s common to keep AUR package repos in `~/aur-packages`:
     ```bash
     mkdir -p ~/aur-packages
     cd ~/aur-packages
     ```

5. **Clone the AUR Git Repository for Your Package**
   - If the package does not exist yet, create it on the AUR website first.
   - Then clone it:
     ```bash
     git clone ssh://aur@aur.archlinux.org/<your-package-name>.git
     cd <your-package-name>
     ```

6. **Write the PKGBUILD File**
   - Create a `PKGBUILD` file describing how to build and install your package.
   - At minimum, specify:
     - `pkgname`, `pkgver`, `pkgrel`, `pkgdesc`, `arch`, `url`, `license`, `depends`, `source`, `sha256sums`
     - Write `build()`, `package()`, and (if needed) `prepare()` functions.
   - If your project uses a `setup.sh`, ensure the PKGBUILD installs it to `/usr/bin/<your-package-name>`.

7. **Generate .SRCINFO**
   - Run:
     ```bash
     makepkg --printsrcinfo > .SRCINFO
     ```

8. **Test Build the Package**
   - Run:
     ```bash
     makepkg -fc
     ```
   - Fix any errors or missing dependencies.

9. **Lint with namcap**
   - Run:
     ```bash
     namcap PKGBUILD
     namcap <your-package-name>-<version>-<arch>.pkg.tar.zst
     ```
   - Address any major warnings.

10. **Commit and Push to AUR**
    - Add and commit your files:
      ```bash
      git add PKGBUILD .SRCINFO
      git commit -m "Initial commit"
      git push origin master
      ```

11. **Maintain Your Package**
    - For updates, increment `pkgver` and reset `pkgrel` to 1, or just increment `pkgrel` for minor changes.
    - Update `.SRCINFO` and push changes as above.

---

## Important Notes and Limitations

*   **`setup.sh` Requirement**: This script explicitly looks for a `setup.sh` file in the root or one subdirectory of your source repository. It installs this `setup.sh` as the main executable for your package (e.g., `/usr/bin/your-package-name`). If your project doesn't have a `setup.sh` or uses a different installation method, you will need to manually edit the generated `PKGBUILD` file.
*   **AUR Account & SSH Key**: You must have an AUR account, and your public SSH key needs to be added to your AUR account settings for the script to successfully push changes. The script attempts to assist with SSH key generation and configuration.
*   **`~/aur-packages` Directory**: The script expects to work within a `~/aur-packages` directory where your AUR package repositories are cloned. Ensure this directory exists or is created.
*   **Error Handling**: The script includes basic error handling and will exit if critical steps fail (e.g., cloning AUR repo, invalid URLs).
*   **`namcap` Warnings**: While `namcap` issues are reported, the script continues the process. It's recommended to address `namcap` warnings manually.
*   **Complete Cleanup**: If `makepkg -fc` fails during the test and clean phase, the script offers an option for a more aggressive cleanup, including removing `src/`, `pkg/`, and Git-related files.
*   **Version and `pkgrel` Management**: The script automates `pkgver` and `pkgrel` updates. Be mindful of how you input new versions; the script will handle `pkgrel` increments or resets accordingly.
*   **Git Upstream**: The script sets `origin master` as the upstream for pushes.