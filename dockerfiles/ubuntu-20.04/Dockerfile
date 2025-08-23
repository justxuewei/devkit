FROM ubuntu:20.04

ARG UID=1000
ARG GID=1000

# Replace sh with bash
RUN rm /bin/sh \
    && ln -s /bin/bash /bin/sh

# Switch to Ali ubuntu sources
ADD sources.list /root/sources.list
RUN mv /etc/apt/sources.list  /etc/apt/sources.list_bak
RUN cp /root/sources.list  /etc/apt/sources.list

RUN apt-get update
RUN apt-get install -y gcc automake autoconf libtool make \
      bison flex libelf-dev bc build-essential libncurses-dev \
      libssl-dev python3 openssl dwarves libglib2.0 ninja-build \
      python3-venv pkg-config python3-pip texinfo

RUN pip3 install meson

# Use non-root user
RUN groupadd -r -g $GID nonroot \
    && useradd -r -u $UID -g nonroot -d /home/nonroot -s /bin/bash nonroot
RUN mkdir -p /home/nonroot \
    && chown -R nonroot:nonroot /home/nonroot
USER nonroot

WORKDIR /home/nonroot

RUN touch .bashrc

CMD ["bash"]

