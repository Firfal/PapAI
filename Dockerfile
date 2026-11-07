# Backend PapAI uniquement.
#
# Ni pyautogui ni mss ici : ils exigent un écran et ne s'installent pas sur un
# serveur. Le code qui touche la souris vit sur le PC de la personne aidée, et
# nulle part ailleurs — c'est aussi ce qui fait qu'un serveur compromis ne peut
# pas cliquer sur son bureau.

FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY requirements-backend.txt .
RUN pip install --no-cache-dir -r requirements-backend.txt

COPY papai_tools.py .
COPY backend/ ./backend/
COPY extension/sites_connus.json ./extension/sites_connus.json

# L'hébergeur impose le port par $PORT ; 8000 en local.
ENV PORT=8000
EXPOSE 8000

CMD ["sh", "-c", "uvicorn backend.app:app --host 0.0.0.0 --port ${PORT} --log-level warning"]
