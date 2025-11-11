FROM python:3.11-slim

RUN apt-get update
RUN apt-get -y upgrade

COPY requirements.txt /requirements.txt
COPY main /main

RUN pip install --upgrade pip
RUN pip install --root-user-action=ignore --pre c8y_api
RUN pip install --root-user-action=ignore -r requirements.txt

ENTRYPOINT ["python", "-u", "/main/main.py"]
