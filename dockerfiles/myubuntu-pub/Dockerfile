FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    python3 \
    dnsutils \
    less \
    strace \
    vim \
    lsof \
    iproute2 \
    curl \
    git \
    iputils-ping

ENV GOLANG_VERSION=1.24.3
RUN curl -fsSL https://go.dev/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz | tar -C /usr/local -xzf -
ENV PATH=/usr/local/go/bin:$PATH
RUN go env -w GO111MODULE=on

ENV NVM_DIR=/root/.nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash && \
    . "$NVM_DIR/nvm.sh" && \
    nvm install --lts

RUN mkdir -p /root/.ssh && chmod 700 /root/.ssh

CMD ["sleep", "infinity"]
