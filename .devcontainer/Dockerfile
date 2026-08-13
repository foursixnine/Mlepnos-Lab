FROM registry.opensuse.org/opensuse/tumbleweed:latest

# Install minimal build tools and Perl + cpanminus
RUN zypper -n ref \
 && zypper -n in -t pattern devel_C_C++ perl perl-App-cpanminus git make gcc \
 && zypper clean -a

# Create a non-root user 'vscode' to match Codespaces/Copilot Spaces
RUN useradd -m -G users,wheel vscode || true
USER vscode
WORKDIR /workspace

# Ensure cpanm is available for the vscode user
ENV PATH="/home/vscode/.local/bin:${PATH}"

CMD ["/bin/bash"]
