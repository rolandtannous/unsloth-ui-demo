# """
# Colab-specific helpers for running Unsloth UI.
# """
#
# from pathlib import Path
#
#
# def start(port: int = 8000):
#     """
#     Start Unsloth UI server in Colab.
#
#     Usage:
#         from colab import start
#         start()
#     """
#     import sys
#
#     sys.path.insert(0, str(Path(__file__).parent))
#
#     from run import run_server
#
#     # Auto-detect frontend path
#     repo_root = Path(__file__).parent.parent
#     frontend_path = repo_root / "frontend" / "build"
#
#     run_server(host="0.0.0.0", port=port, frontend_path=frontend_path)
#
#     # Open UI
#     try:
#         from google.colab import output
#
#         print("🦥 Opening Unsloth UI...")
#         output.serve_kernel_port_as_window(port)
#         print("=" * 50)
#         print(
#             f"🦥 Open https://localhost:{port} in your browser to access Unsloth Studio"
#         )
#         print("=" * 50)
#     except ImportError:
#         print(f"🦥 Open https://localhost:{port} in your browser")

"""
Colab-specific helpers for running Unsloth UI.
"""
from pathlib import Path


def get_colab_url(port: int = 8000) -> str:
    """
    Get the actual Colab proxy URL for a port.

    Returns:
        The real URL like https://8000-m-s-xxx.us-central1-1.prod.colab.dev/
    """
    try:
        from google.colab.output import eval_js

        url = eval_js(f"google.colab.kernel.proxyPort({port})")
        return url
    except Exception:
        return f"http://localhost:{port}"


def show_link(port: int = 8000):
    """Display a styled clickable link to the UI."""
    from IPython.display import display, HTML

    url = get_colab_url(port)

    html = f"""
    <div style="padding: 20px; background: linear-gradient(135deg, #22c55e 0%, #16a34a 100%);
                border-radius: 12px; margin: 10px 0; font-family: system-ui, -apple-system, sans-serif;">
        <h2 style="color: white; margin: 0 0 12px 0; font-size: 24px;">
            🦥 Unsloth UI is Ready!
        </h2>
        <a href="{url}" target="_blank"
           style="display: inline-block; padding: 14px 28px; background: white; color: #16a34a;
                  text-decoration: none; border-radius: 8px; font-weight: 600; font-size: 16px;
                  box-shadow: 0 4px 6px rgba(0,0,0,0.1); transition: transform 0.2s;">
            🚀 Open Unsloth UI
        </a>
        <p style="color: rgba(255,255,255,0.9); margin: 16px 0 0 0; font-size: 13px;
                  word-break: break-all; font-family: monospace;">
            {url}
        </p>
    </div>
    """
    display(HTML(html))


def start(port: int = 8000):
    """
    Start Unsloth UI server in Colab and display the URL.

    Usage:
        from colab import start
        start()
    """
    import sys

    # Add backend to path
    backend_path = str(Path(__file__).parent)
    if backend_path not in sys.path:
        sys.path.insert(0, backend_path)

    from run import run_server

    # Auto-detect frontend path
    repo_root = Path(__file__).parent.parent
    frontend_path = repo_root / "frontend" / "build"

    # Start server silently
    run_server(host="0.0.0.0", port=port, frontend_path=frontend_path, silent=True)

    # Show the clickable link with real URL
    show_link(port)
