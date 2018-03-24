FROM debian
RUN apt-get update
RUN apt-get install -y git cmake sudo wget curl bzip2 xz-utils build-essential
COPY . /vdpm
WORKDIR /vdpm
RUN bash ./bootstrap-vitasdk.sh
RUN echo "export VITASDK=/usr/local/vitasdk" >> /root/.bashrc \
 && echo "export PATH=/usr/local/vitasdk/bin:$PATH" >> /root/.bashrc
ENV VITASDK /usr/local/vitasdk
ENV PATH /usr/local/vitasdk/bin:$PATH
RUN bash ./install-all.sh
