# ---------- 1. builder stage ----------
FROM --platform=linux/amd64 python:3.11-slim AS builder

# ビルドに必要なツールをインストール
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  libgomp1 curl libgraphviz-dev \
  && rm -rf /var/lib/apt/lists/*

# 依存関係セットアップ
COPY pyproject.toml poetry.lock ./
RUN pip install --no-cache-dir poetry \
  && poetry config virtualenvs.create false \
  && poetry install --no-root

# 依存性ミスマッチ対応
RUN pip install --no-cache-dir \
  cloudpickle==2.2.1 \
  graphviz==0.20.3 \
  pyarrow==16.1.0

# MLflow からモデルをインポート
ARG MLFLOW_TRACKING_URI
ARG MLFLOW_TOKEN
ENV MLFLOW_TRACKING_URI=${MLFLOW_TRACKING_URI}
ENV MLFLOW_TOKEN=${MLFLOW_TOKEN}

# idempotent にインポート（存在すればスキップ）
RUN python scripts/import_volume_spike_model.py || true

# ---------- 2. runtime stage ----------
FROM --platform=linux/amd64 python:3.11-slim
RUN apt-get update && \
  apt-get install -y --no-install-recommends libgomp1 graphviz && \
  rm -rf /var/lib/apt/lists/*

# ランタイムに必要なライブラリのみコピー
COPY --from=builder /usr/local/lib/python3.11/site-packages/ \
  /usr/local/lib/python3.11/site-packages/

# bentoml CLI をコピー
COPY --from=builder /usr/local/bin/bentoml /usr/local/bin/

# アプリケーションファイル
WORKDIR /app
ENV BENTOML_HOME=/bentoml

COPY bentofile.yaml ./
COPY services/ services/
COPY scripts/ scripts/

RUN chmod +x scripts/start_bento.sh scripts/import_volume_spike_model.py

EXPOSE 3000
ENTRYPOINT ["sh", "-c", "scripts/start_bento.sh"]
