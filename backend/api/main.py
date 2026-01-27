from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pathlib import Path
from datetime import datetime
import torch
import platform
import psutil

# Create FastAPI app
app = FastAPI(title="Unsloth UI Demo", version="1.0.0")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============ API Routes ============


@app.get("/api/health")
async def health_check():
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}


@app.get("/api/system")
async def get_system_info():
    gpu_info = {"available": False, "devices": []}
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


def setup_frontend(app: FastAPI, build_path: Path):
    """Mount frontend static files"""
    if build_path.exists():
        # Mount assets
        assets_dir = build_path / "assets"
        if assets_dir.exists():
            app.mount("/assets", StaticFiles(directory=assets_dir), name="assets")

        @app.get("/")
        async def serve_root():
            return FileResponse(build_path / "index.html")

        @app.get("/{full_path:path}")
        async def serve_frontend(full_path: str):
            if full_path.startswith("api"):
                return {"error": "API endpoint not found"}

            file_path = build_path / full_path
            if file_path.is_file():
                return FileResponse(file_path)

            return FileResponse(build_path / "index.html")

        return True
    return False
