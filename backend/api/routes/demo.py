from fastapi import APIRouter
import torch
import platform
import psutil
from datetime import datetime

router = APIRouter()


@router.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.now().isoformat()}


@router.get("/system")
async def get_system_info():
    """Get system information"""

    # GPU Info
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

    # CPU & Memory
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


@router.post("/echo")
async def echo_message(data: dict):
    """Echo back the received data"""
    return {
        "received": data,
        "message": f"Hello! You sent: {data.get('text', 'nothing')}",
        "timestamp": datetime.now().isoformat(),
    }


@router.get("/models")
async def list_models():
    """List available models (demo)"""
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


@router.post("/train/start")
async def start_training(config: dict):
    """Simulate starting a training job"""
    return {
        "status": "started",
        "job_id": "demo_job_001",
        "config": config,
        "message": "Training simulation started (this is a demo)",
    }


@router.get("/train/status")
async def get_training_status():
    """Get training status (demo)"""
    return {"status": "idle", "message": "No training in progress", "last_run": None}
