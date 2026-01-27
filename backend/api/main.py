from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from pathlib import Path
import os

from api.routes import demo_router
from api.core.config import settings

app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
)

# CORS - Allow all origins for Colab compatibility
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# API Routes
app.include_router(demo_router, prefix="/api", tags=["demo"])

# Serve React frontend
FRONTEND_BUILD = Path(__file__).parent.parent.parent / "frontend" / "build"

if FRONTEND_BUILD.exists():
    # Serve static files
    app.mount(
        "/static", StaticFiles(directory=FRONTEND_BUILD / "static"), name="static"
    )

    @app.get("/")
    async def serve_root():
        return FileResponse(FRONTEND_BUILD / "index.html")

    @app.get("/{full_path:path}")
    async def serve_frontend(full_path: str):
        # Don't catch API routes
        if full_path.startswith("api"):
            return {"error": "Not found"}

        # Check if file exists
        file_path = FRONTEND_BUILD / full_path
        if file_path.is_file():
            return FileResponse(file_path)

        # Return index.html for React Router
        return FileResponse(FRONTEND_BUILD / "index.html")

else:

    @app.get("/")
    async def no_frontend():
        return {
            "message": "API is running! Frontend not built yet.",
            "docs": "/docs",
            "health": "/api/health",
        }
