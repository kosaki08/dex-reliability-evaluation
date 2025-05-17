locals {
  env = terraform.workspace
}

# プロジェクトサービス
module "project_services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 14.0"

  project_id = local.project_id
  activate_apis = [
    "cloudresourcemanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "vpcaccess.googleapis.com",
    "iamcredentials.googleapis.com",
    "secretmanager.googleapis.com",
  ]
}

# VPC ネットワーク
module "network" {
  source                  = "./modules/network"
  project_id              = local.project_id
  region                  = local.region
  network_name            = "dex-network-${local.env}"
  vpc_connector_name      = "serverless-conn-${local.env}"
  subnet_ip_cidr_range    = "10.9.0.0/24"
  connector_ip_cidr_range = "10.8.0.0/28"
}

# サービスアカウント
module "service_accounts" {
  source     = "./modules/service_accounts"
  project_id = local.project_id
  sa_names   = ["bento", "streamlit", "airflow"]
  env        = local.env
}

# Secret モジュール
module "secrets" {
  source     = "./modules/secrets"
  project_id = local.project_id

  accessors = {
    # Streamlit SA へ snowflake-pass / snowflake-user の accessor を付与
    "snowflake-pass" = [module.service_accounts.emails["streamlit"]]
    "snowflake-user" = [module.service_accounts.emails["streamlit"]]

    # Bento SA へ mlflow-token の accessor を付与
    "mlflow-token" = [module.service_accounts.emails["bento"]]
  }
}

# Artifact Registry
module "artifact_registry" {
  source  = "GoogleCloudPlatform/artifact-registry/google"
  version = "~> 0.3"

  project_id    = local.project_id
  location      = local.region
  format        = "DOCKER"
  repository_id = "portfolio-docker-${local.env}" # dev|prod
}

# BentoML API
module "cloud_run_bento" {
  source                = "./modules/cloud_run"
  project_id            = local.project_id
  name                  = "bento-api-${local.env}"
  location              = local.region
  image                 = "asia-northeast1-docker.pkg.dev/${local.project_id}/portfolio-docker-${local.env}/bento:latest"
  vpc_connector         = module.network.connector_id
  container_port        = 3000
  service_account_email = module.service_accounts.emails["bento"]


  depends_on = [
    module.artifact_registry,
    module.secrets
  ]

  env_vars = {
    MLFLOW_TRACKING_URI = "https://mlflow-${local.env}-${local.region}.run.app"
  }

  secret_env_vars = {
    MLFLOW_TOKEN = {
      secret  = "mlflow-token"
      version = "latest"
    }
  }
}

# Streamlit ダッシュボード
module "cloud_run_streamlit" {
  source         = "./modules/cloud_run"
  project_id     = local.project_id
  name           = "streamlit-${local.env}"
  location       = local.region
  image          = "asia-northeast1-docker.pkg.dev/${local.project_id}/portfolio-docker-${local.env}/streamlit:${var.image_tag}"
  container_port = 8501

  # VPC アクセスコネクタ
  vpc_connector = module.network.connector_id

  # サービスアカウントを指定
  service_account_email = module.service_accounts.emails["streamlit"]

  env_vars = {
    BENTO_API_URL = "https://bento-api-${local.env}-${local.region}.run.app/predict"
  }

  secret_env_vars = {
    SNOWFLAKE_PASSWORD = {
      secret  = "snowflake-pass"
      version = "latest"
    }
    SNOWFLAKE_USER = {
      secret  = "snowflake-user"
      version = "latest"
    }
  }

  depends_on = [
    module.artifact_registry,
    module.secrets
  ]
}

# MLflow
module "cloud_run_mlflow" {
  source         = "./modules/cloud_run"
  project_id     = local.project_id
  name           = "mlflow-${local.env}"
  location       = local.region
  image          = "asia-northeast1-docker.pkg.dev/${local.project_id}/portfolio-docker-${local.env}/mlflow:${var.image_tag}"
  container_port = 5000

  vpc_connector = module.network.connector_id

  env_vars = {
    ARTIFACT_ROOT        = "gs://${local.artifacts_bucket}/mlflow-artifacts"
    BACKEND_DATABASE_URL = "postgresql://user:pass@host:5432/mlflow"
  }

  depends_on = [
    module.artifact_registry,
  ]
}
