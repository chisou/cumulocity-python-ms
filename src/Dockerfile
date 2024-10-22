FROM python:3.10-slim

RUN apt-get update && apt-get -y upgrade

COPY requirements.txt /
COPY main /main

RUN pip install --upgrade pip
RUN pip install -r requirements.txt

ENTRYPOINT ["python", "-u", "/main/main.py"]
