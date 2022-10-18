# Matrix Coturn Docker

Dockerized Coturn server for an existing Matrix install.

Coturn will allow your Matrix instance to perform audio and video calls.

## Getting started

Due to the number of ports that must be exposed, I recommend you to dedicate one VPS/server for your COTURN server.

1. Generate SSL certificates

    ```bash
    mkdir -p ./ssl
    openssl genrsa -out ./ssl/coturn.key.pem 4096
    openssl req -new -x509 -sha256 -days 1095 -subj "/C=FR/ST=IDF/L=PARIS/O=EXAMPLE/CN=Coturn" -key ./ssl/coturn.key.pem -out ./ssl/coturn.crt.pem
    ```

2. Run setup scripts

    ```bash
    # Generate random identifiers for Coturn 
    # (replace "1.2.3.4" by your public TURN server IP address)
    ./tools/docker-prepare.sh matrix.yourdomain.com turn.yourdomain.com 1.2.3.4

    # Start coturn (wait it is running)
    chmod -R 755 ./ssl
    docker-compose up -d

    # Add coturn user
    chmod +x ./turn_add_missing_user.sh && ./turn_add_missing_user.sh
    ```

3. Update your Matrix/Synapse server configuration

    Copy the `./synapse/voip.yaml` file to your Synapse `synapse/conf/homeserver.d/voip.yaml` configuration. Restart it and enjoy calls.

## Credits

- Inspired from [Miouyouyou's repo](https://github.com/Miouyouyou/matrix-coturn-docker-setup)
