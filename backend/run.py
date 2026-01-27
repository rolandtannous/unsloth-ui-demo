# """
# Run script for Unsloth UI backend.
# Works in both local and Colab environments.
# """
#
# import sys
# from pathlib import Path
#
#
# def run_server(host: str = "0.0.0.0", port: int = 8000, frontend_path: Path = None):
#     """
#     Start the FastAPI server.
#
#     Args:
#         host: Host to bind to
#         port: Port to bind to
#         frontend_path: Path to frontend build directory
#     """
#     import nest_asyncio
#
#     nest_asyncio.apply()
#
#     import asyncio
#     from threading import Thread
#     import time
#     import uvicorn
#
#     from api.main import app, setup_frontend
#
#     # Setup frontend if path provided
#     if frontend_path:
#         if setup_frontend(app, frontend_path):
#             print(f"✅ Frontend loaded from {frontend_path}")
#         else:
#             print(f"⚠️ Frontend not found at {frontend_path}")
#
#     # Run server
#     def _run():
#         config = uvicorn.Config(app, host=host, port=port, log_level="warning")
#         server = uvicorn.Server(config)
#         asyncio.run(server.serve())
#
#     thread = Thread(target=_run, daemon=True)
#     thread.start()
#     time.sleep(3)
#
#     # print("")
#     print("=" * 50)
#     print(f"🦥 Backend Server started on port {port}")
#     print("=" * 50)
#
#     return app
#
#
# # For direct execution
# if __name__ == "__main__":
#     import argparse
#
#     parser = argparse.ArgumentParser(description="Run Unsloth UI server")
#     parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
#     parser.add_argument("--port", type=int, default=8000, help="Port to bind to")
#     parser.add_argument(
#         "--frontend", type=str, default=None, help="Path to frontend build"
#     )
#
#     args = parser.parse_args()
#
#     frontend_path = Path(args.frontend) if args.frontend else None
#     run_server(host=args.host, port=args.port, frontend_path=frontend_path)
#
#     # Keep running
#     import time
#
#     while True:
#         time.sleep(1)

"""
Run script for Unsloth UI backend.
Works in both local and Colab environments.
"""
import sys
from pathlib import Path


def run_server(
    host: str = "0.0.0.0",
    port: int = 8000,
    frontend_path: Path = None,
    silent: bool = False,
):
    """
    Start the FastAPI server.

    Args:
        host: Host to bind to
        port: Port to bind to
        frontend_path: Path to frontend build directory
        silent: Suppress startup messages
    """
    import nest_asyncio

    nest_asyncio.apply()

    import asyncio
    from threading import Thread
    import time
    import uvicorn

    from api.main import app, setup_frontend

    # Setup frontend if path provided
    if frontend_path:
        if setup_frontend(app, frontend_path):
            if not silent:
                print(f"✅ Frontend loaded from {frontend_path}")
        else:
            if not silent:
                print(f"⚠️ Frontend not found at {frontend_path}")

    # Run server
    def _run():
        config = uvicorn.Config(app, host=host, port=port, log_level="warning")
        server = uvicorn.Server(config)
        asyncio.run(server.serve())

    thread = Thread(target=_run, daemon=True)
    thread.start()
    time.sleep(3)

    if not silent:
        print("")
        print("=" * 50)
        print(f"🦥 Server is running on port {port}")
        print("=" * 50)

    return app


# For direct execution
if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="Run Unsloth UI server")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    parser.add_argument("--port", type=int, default=8000, help="Port to bind to")
    parser.add_argument(
        "--frontend", type=str, default=None, help="Path to frontend build"
    )
    parser.add_argument("--silent", action="store_true", help="Suppress output")

    args = parser.parse_args()

    frontend_path = Path(args.frontend) if args.frontend else None
    run_server(
        host=args.host, port=args.port, frontend_path=frontend_path, silent=args.silent
    )

    # Keep running
    import time

    while True:
        time.sleep(1)
