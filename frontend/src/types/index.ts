export interface HealthResponse {
  status: string;
  timestamp: string;
}

export interface GpuDevice {
  index: number;
  name: string;
  memory_total_gb: number;
}

export interface GpuInfo {
  available: boolean;
  devices: GpuDevice[];
}

export interface MemoryInfo {
  total_gb: number;
  available_gb: number;
  percent_used: number;
}

export interface SystemInfo {
  platform: string;
  python_version: string;
  cpu_count: number;
  memory: MemoryInfo;
  gpu: GpuInfo;
}

export interface EchoResponse {
  received: Record<string, unknown>;
  message: string;
  timestamp: string;
}

export interface Model {
  id: string;
  name: string;
  size?: string;
  description?: string;
}

export interface ModelsResponse {
  models: Model[];
}

export interface TrainingConfig {
  model_name: string;
  dataset: string;
  max_seq_length: number;
  learning_rate: number;
  num_epochs: number;
  batch_size: number;
  lora_r: number;
  lora_alpha: number;
}

export interface TrainingStatus {
  status: string;
  message: string;
  job_id?: string;
}
