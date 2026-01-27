import type {
  HealthResponse,
  SystemInfo,
  EchoResponse,
  ModelsResponse,
  TrainingConfig,
  TrainingStatus,
} from "../types";

const API_BASE = "";

class ApiService {
  private async request<T>(
    endpoint: string,
    options: RequestInit = {},
  ): Promise<T> {
    const response = await fetch(`${API_BASE}${endpoint}`, {
      headers: {
        "Content-Type": "application/json",
        ...options.headers,
      },
      ...options,
    });

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    return response.json();
  }

  // Health & System
  health(): Promise<HealthResponse> {
    return this.request<HealthResponse>("/api/health");
  }

  getSystemInfo(): Promise<SystemInfo> {
    return this.request<SystemInfo>("/api/system");
  }

  // Models
  getModels(): Promise<ModelsResponse> {
    return this.request<ModelsResponse>("/api/models");
  }

  // Training
  startTraining(config: TrainingConfig): Promise<TrainingStatus> {
    return this.request<TrainingStatus>("/api/train/start", {
      method: "POST",
      body: JSON.stringify(config),
    });
  }

  getTrainingStatus(): Promise<TrainingStatus> {
    return this.request<TrainingStatus>("/api/train/status");
  }

  // Echo (for testing)
  echo(text: string): Promise<EchoResponse> {
    return this.request<EchoResponse>("/api/echo", {
      method: "POST",
      body: JSON.stringify({ text }),
    });
  }
}

export const api = new ApiService();
