"""
Unsloth Studio - FastAPI backend that serves API routes and the React frontend.
"""

import webbrowser
import threading
from pathlib import Path
from datetime import datetime

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import uvicorn

app = FastAPI(title="Unsloth Studio", version="0.1.0")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Path to the pre-built React frontend
FRONTEND_DIR = Path(__file__).parent.parent / "frontend" / "build"


# ============ API Routes ============


@app.get("/api/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}


@app.get("/api/system")
async def get_system_info():
    import platform
    import psutil

    gpu_info = {"available": False, "devices": []}
    try:
        import torch

        if torch.cuda.is_available():
            gpu_info["available"] = True
            for i in range(torch.cuda.device_count()):
                props = torch.cuda.get_device_properties(i)
                gpu_info["devices"].append(
                    {
                        "index": i,
                        "name": props.name,
                        "memory_total_gb": round(props.total_memory / 1e9, 2),
                    }
                )
    except ImportError:
        pass

    memory = psutil.virtual_memory()

    return {
        "platform": platform.platform(),
        "python_version": platform.python_version(),
        "cpu_count": psutil.cpu_count(),
        "memory": {
            "total_gb": round(memory.total / 1e9, 2),
            "available_gb": round(memory.available / 1e9, 2),
            "percent_used": memory.percent,
        },
        "gpu": gpu_info,
    }


@app.post("/api/echo")
async def echo_message(data: dict):
    return {
        "received": data,
        "message": f"Hello! You sent: {data.get('text', 'nothing')}",
        "timestamp": datetime.now().isoformat(),
    }


@app.get("/api/models")
async def list_models():
    return {
        "models": [
            {
                "id": "unsloth/llama-3-8b-bnb-4bit",
                "name": "Llama 3 8B (4-bit)",
                "size": "4.5 GB",
                "description": "Fast 4-bit quantized Llama 3",
            },
            {
                "id": "unsloth/mistral-7b-bnb-4bit",
                "name": "Mistral 7B (4-bit)",
                "size": "3.8 GB",
                "description": "Efficient Mistral model",
            },
            {
                "id": "unsloth/gemma-7b-bnb-4bit",
                "name": "Gemma 7B (4-bit)",
                "size": "4.2 GB",
                "description": "Google's Gemma model",
            },
        ]
    }


@app.post("/api/train/start")
async def start_training(config: dict):
    return {
        "status": "started",
        "job_id": f"job_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
        "message": "Training simulation started (this is a demo)",
    }


@app.get("/api/train/status")
async def get_training_status():
    return {"status": "idle", "message": "No training in progress"}


# ============ Serve Frontend ============

# Mount static assets if frontend build exists
if (FRONTEND_DIR / "assets").exists():
    app.mount("/assets", StaticFiles(directory=FRONTEND_DIR / "assets"), name="assets")


@app.get("/")
async def serve_root():
    return FileResponse(FRONTEND_DIR / "index.html")


@app.get("/{full_path:path}")
async def serve_frontend(full_path: str):
    if full_path.startswith("api"):
        return {"error": "API endpoint not found"}

    file_path = FRONTEND_DIR / full_path
    if file_path.is_file():
        return FileResponse(file_path)

    return FileResponse(FRONTEND_DIR / "index.html")


# ============ Server Launcher ============


def start_studio(host: str = "127.0.0.1", port: int = 8000):
    """Start the Unsloth Studio server."""
    url = f"http://{host}:{port}"

    print(f"Starting Unsloth Studio at {url}")
    print(f"Serving frontend from: {FRONTEND_DIR}")

    # Open browser after a short delay
    def open_browser():
        import time

        time.sleep(1.5)
        webbrowser.open(url)

    threading.Thread(target=open_browser, daemon=True).start()

    uvicorn.run(app, host=host, port=port, log_level="info")
