FROM golang:1.23

# Copy the repository files
COPY . /tmp/distributed-tracing-qe

WORKDIR /tmp

# Set the Go path and Go cache environment variables
ENV GOPATH=/tmp/go
ENV GOBIN=/tmp/go/bin
ENV GOCACHE=/tmp/.cache/go-build
ENV PATH=$PATH:$GOBIN

# Create the /tmp/go/bin and build cache directories, and grant read and write permissions to all users
RUN mkdir -p /tmp/go/bin $GOCACHE \
    && chmod -R 777 /tmp/go/bin $GOPATH $GOCACHE

# Install dependencies required by test cases and debugging
RUN apt-get update && apt-get install -y jq vim libreadline-dev unzip

# Install chainsaw
RUN curl -L -o chainsaw.tar.gz https://github.com/kyverno/chainsaw/releases/download/v0.2.12/chainsaw_linux_amd64.tar.gz \
    && tar -xvzf chainsaw.tar.gz \
    && chmod +x chainsaw \
    && mv chainsaw /usr/local/bin/

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install

# Install kubectl and oc
RUN curl -LO https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/openshift-client-linux.tar.gz \
    && tar -xzf openshift-client-linux.tar.gz \
    && chmod +x oc kubectl \
    && mv oc kubectl /usr/local/bin/

# Set the working directory
WORKDIR /tmp/distributed-tracing-qe
