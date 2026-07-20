FROM ubuntu:22.04

# Proxy-Variablen initialisieren
ENV DEBIAN_FRONTEND=noninteractive

# Installiere QEMU-KVM, System-Tools & SSH Server
RUN apt-get update && apt-get install -y \
    qemu-system-x86 \
    qemu-utils \
    openssh-server \
    git \
    build-essential \
    curl \
    jq \
    sudo \
    snapd

# Ordner für den SSH-Dienst vorbereiten
RUN mkdir /var/run/sshd

# Erstelle den Standard-User 'boschrexroth' und vergebe Sudo-Rechte
RUN useradd -m -s /bin/bash boschrexroth && \
    echo "boschrexroth:boschrexroth" | chpasswd && \
    usermod -aG sudo boschrexroth && \
    echo "boschrexroth ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# SSH-Key für die passwortlose Anmeldung aus VS Code kopieren
RUN mkdir -p /home/boschrexroth/.ssh
COPY id_rsa_ctrlx.pub /home/boschrexroth/.ssh/authorized_keys
RUN chown -R boschrexroth:boschrexroth /home/boschrexroth/.ssh && \
    chmod 700 /home/boschrexroth/.ssh && \
    chmod 600 /home/boschrexroth/.ssh/authorized_keys

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
