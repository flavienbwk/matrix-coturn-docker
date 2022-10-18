FROM coturn/coturn:4.6.0

USER root

RUN apt-get update && apt-get -y install sqlite3 libsqlite3-dev libssl-dev

USER nobody:nogroup

VOLUME ["/var/lib/coturn"]

ENTRYPOINT ["docker-entrypoint.sh"]

CMD ["--log-file=stdout", "--external-ip=$(detect-external-ip)"]
