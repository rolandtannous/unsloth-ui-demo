from pathlib import Path


class Settings:
    PROJECT_NAME: str = "Unsloth UI Demo"
    VERSION: str = "1.0.0"
    API_PREFIX: str = "/api"

    # For Colab, we'll use /content as workspace
    WORKSPACE_DIR: Path = Path.home() / ".unsloth_demo"

    def setup_directories(self):
        self.WORKSPACE_DIR.mkdir(parents=True, exist_ok=True)


settings = Settings()
