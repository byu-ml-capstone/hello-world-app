FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# main.py imports from notes_dao.py; the glob picks up modules students add.
COPY *.py ./

# Schema migration SQL files. Applied by notes_dao.apply_migrations() on
# startup — see the lifespan hook in main.py. These live with the service
# that owns the database.
COPY migrations/ ./migrations/

EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8001/health').read()" || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
