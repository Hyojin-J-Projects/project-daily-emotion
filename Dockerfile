FROM python:3.11-slim

# 작업 디렉토리 설정
WORKDIR /code

# 필수 패키지 설치를 위한 종속성 복사
COPY ./requirements.txt /code/requirements.txt

# 패키지 설치 (캐시 제거로 빌드 경량화)
RUN pip install --no-cache-dir --upgrade -r /code/requirements.txt

# 전역 권한 부여 (허깅페이스 보안 규정 대응)
RUN mkdir -p /.cache && chmod -R 777 /.cache

# 프로젝트 전체 코드 복사
COPY . .

# 허깅페이스 스페이스 전용 포트(7860)로 Uvicorn 가동
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "7860"]