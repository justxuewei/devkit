FROM ubuntu:24.04
 
ENV DEBIAN_FRONTEND=noninteractive
 
RUN apt-get update && apt-get install -y \
    python3 \
    dnsutils \
    less \
    strace \
    vim \
    lsof \
    iproute2

ENTRYPOINT ["sleep", "infinity"]
