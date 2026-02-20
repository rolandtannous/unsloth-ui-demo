"""Unsloth CLI entry point."""

import sys
import argparse


def main():
    parser = argparse.ArgumentParser(description="Unsloth CLI")
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # Studio subcommand
    studio_parser = subparsers.add_parser("studio", help="Launch Unsloth Studio")
    studio_parser.add_argument("--port", type=int, default=8000, help="Port number")
    studio_parser.add_argument("--host", default="127.0.0.1", help="Host address")

    # Install subcommand
    install_parser = subparsers.add_parser(
        "install",
        help="Install all dependencies in the correct order",
    )
    install_parser.add_argument(
        "--skip-patch",
        action="store_true",
        default=False,
        help="Skip the llama_cpp.py patch step",
    )
    install_parser.add_argument(
        "--dry-run",
        action="store_true",
        default=False,
        help="Show what would be done without actually running pip commands",
    )

    args = parser.parse_args()

    if args.command == "studio":
        from roland_ui_demo.studio.backend.main import start_studio

        start_studio(host=args.host, port=args.port)
    elif args.command == "install":
        from roland_ui_demo.installer import run_install

        return run_install(
            skip_patch=args.skip_patch,
            dry_run=args.dry_run,
        )
    else:
        parser.print_help()
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
