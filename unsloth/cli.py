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

    args = parser.parse_args()

    if args.command == "studio":
        from unsloth.studio.backend.main import start_studio

        start_studio(host=args.host, port=args.port)
    else:
        parser.print_help()
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
