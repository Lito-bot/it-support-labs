FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY parcelo ./parcelo
COPY tests ./tests
COPY pytest.ini .
RUN useradd --create-home parcelo
USER parcelo
CMD ["uvicorn", "parcelo.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
