#!/bin/bash
set -e

if [ -e "/opt/airflow/requirements.txt" ]; then
  pip install --upgrade pip
  pip install -r /opt/airflow/requirements.txt
fi

airflow db upgrade

if ! airflow users list | grep -q "admin"; then
  airflow users create \
    --username admin \
    --firstname admin \
    --lastname admin \
    --role Admin \
    --email admin@example.com \
    --password ${AIRFLOW_ADMIN_PASSWORD}
fi

exec airflow webserver