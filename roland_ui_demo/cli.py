"""Unsloth Studio CLI entry point."""

import sys
import argparse


def main():
    parser = argparse.ArgumentParser(
        prog="unsloth-roland-test",
        description="Unsloth Studio CLI",
    )
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # ── studio subcommand (with its own sub-subcommands) ──
    studio_parser = subparsers.add_parser("studio", help="Unsloth Studio commands")
    studio_subparsers = studio_parser.add_subparsers(
        dest="studio_command", help="Studio commands"
    )

    # studio install
    install_parser = studio_subparsers.add_parser(
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

    # studio (launch) — default when no sub-subcommand is given
    studio_parser.add_argument(
        "--port", "-p", type=int, default=8000, help="Port number (default: 8000)"
    )
    studio_parser.add_argument(
        "--host", "-H", default="0.0.0.0", help="Host address (default: 0.0.0.0)"
    )

    args = parser.parse_args()

    if args.command == "studio":
        if args.studio_command == "install":
            from roland_ui_demo.installer import run_install

            return run_install(
                skip_patch=args.skip_patch,
                dry_run=args.dry_run,
            )
        else:
            # No sub-subcommand → launch the studio server
            from roland_ui_demo.studio.backend.main import start_studio

            start_studio(host=args.host, port=args.port)
    else:
        parser.print_help()
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
