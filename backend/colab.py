"""
Colab-specific helpers for running Unsloth UI.
"""

from pathlib import Path


def start(port: int = 8000):
    """
    Start Unsloth UI server in Colab.

    Usage:
        from colab import start
        start()
    """
    import sys

    sys.path.insert(0, str(Path(__file__).parent))

    from run import run_server

    # Auto-detect frontend path
    repo_root = Path(__file__).parent.parent
    frontend_path = repo_root / "frontend" / "build"

    run_server(host="0.0.0.0", port=port, frontend_path=frontend_path)

    # Open UI
    # try:
    #     from google.colab import output
    #
    #     print("🦥 Opening Unsloth UI...")
    #     output.serve_kernel_port_as_window(port)
    #     print("=" * 50)
    #     print(
    #         f"🦥 Open https://localhost:{port} in your browser to access Unsloth Studio"
    #     )
    #     print("=" * 50)
    # except ImportError:
    #     print(f"🦥 Open https://localhost:{port} in your browser")

    try:
        from google.colab.output import eval_js
        from IPython.display import HTML

        port = 3000
        url = eval_js(f"google.colab.kernel.proxyPort({port}, {{'cache': false}})")
        HTML(
            f'<a href="{url.rstrip("/")}/" target="_blank" rel="noopener">Open app in new tab</a>'
        )
    except:
        print(f"Failed to start Unsloth Studio.")
