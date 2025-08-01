# GitHub Repository Setup

## Overview

This repository includes scripts, templates, and context files to orchestrate AI-assisted "ritual" logs using Goblin and Wizard personas. It provides tools to manage session context, generate logs, and automate interactions with language models.

## Project Structure

- `ritualc.sh`: Main entrypoint script for running ritual orchestration.
- `Scripts/`: Contains ritual scripts and chat orchestration helpers.
- `Templates/`: JSON templates for ritual and conjuration logs.
- `Context/`: Generated ritual and conjuration log files (ignored in version control).
- `requirements.txt`: Python dependencies (if extending functionality with Python).
- `.gitignore`: Lists files and directories to exclude from version control.
- `LICENSE`: MIT License for this project.

## Prerequisites

- Bash (≥4.0)
- `jq`: JSON processor (https://stedolan.github.io/jq/)
- `ripgrep` (`rg`) for file discovery
- Git
- [Optional] Python 3 and packages from `requirements.txt`:
  ```sh
  pip install -r requirements.txt
  ```
- [Optional] `ollama` CLI for language model integrations

## Installation

```sh
# Clone the repository
git clone https://github.com/yourusername/your-repo.git
cd your-repo
```

Install required tools:
```sh
# Debian/Ubuntu
sudo apt-get update
sudo apt-get install -y jq ripgrep

# macOS (Homebrew)
brew install jq ripgrep
```

## Usage

Run the main orchestration script:
```sh
./ritualc.sh -r
```
- `-r`: Run the full ritual orchestration.
- `-c "<custom message>"`: Provide a custom message instead of using `query.txt`.
- `-w`: Switch to Wizard role (default is Goblin).
- Without flags, opens `query.txt` for user input.

Logs and outputs are written to the `Context/` directory.

## Contributing

Contributions are welcome! Please open issues or submit pull requests for enhancements.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
