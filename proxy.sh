#!/bin/bash
# Equipo 4 - Proxy inverso con Apache en la VM 7400 (10.10.4.10)
# Publica las 3 paginas por el puerto 80 y cierra los puertos 8081-8083
# para que solo se pueda llegar a ellas a traves del proxy.
#
#   http://10.10.4.10/pagina1/  ->  http://127.0.0.1:8081/
#   http://10.10.4.10/pagina2/  ->  http://127.0.0.1:8082/
#   http://10.10.4.10/pagina3/  ->  http://127.0.0.1:8083/

set -e

echo "== 1. Activando los modulos de proxy de Apache =="
sudo a2enmod proxy proxy_http headers > /dev/null

echo "== 2. Sitio del proxy inverso en el puerto 80 =="
sudo tee /etc/apache2/sites-available/equipo4-proxy.conf > /dev/null <<'CONF'
<VirtualHost *:80>
    ServerName 10.10.4.10
    DocumentRoot /var/www/html

    ProxyPreserveHost On
    ProxyRequests Off

    RedirectMatch ^/pagina([1-3])$ /pagina$1/

    ProxyPass        /pagina1/ http://127.0.0.1:8081/
    ProxyPassReverse /pagina1/ http://127.0.0.1:8081/
    ProxyPass        /pagina2/ http://127.0.0.1:8082/
    ProxyPassReverse /pagina2/ http://127.0.0.1:8082/
    ProxyPass        /pagina3/ http://127.0.0.1:8083/
    ProxyPassReverse /pagina3/ http://127.0.0.1:8083/

    ErrorLog ${APACHE_LOG_DIR}/equipo4-proxy-error.log
    CustomLog ${APACHE_LOG_DIR}/equipo4-proxy-access.log combined
</VirtualHost>
CONF
sudo a2dissite 000-default.conf > /dev/null 2>&1 || true
sudo a2ensite equipo4-proxy.conf > /dev/null

echo "== 3. Las paginas internas solo escuchan en 127.0.0.1 =="
for P in 8081 8082 8083; do
  sudo sed -i "s/^Listen $P$/Listen 127.0.0.1:$P/" /etc/apache2/ports.conf
done

sudo apache2ctl configtest
sudo systemctl restart apache2

echo "== 4. Firewall: solo SSH (22) y el proxy (80) quedan abiertos =="
sudo ufw allow 80/tcp > /dev/null
for P in 8081 8082 8083; do
  sudo ufw delete allow "$P"/tcp > /dev/null 2>&1 || true
done
sudo ufw status

echo "== 5. Prueba =="
for N in 1 2 3; do
  echo "--- http://localhost/pagina$N/"
  curl -s "http://localhost/pagina$N/" | grep -o '<h1>[^<]*\|Conectado a MySQL' | sed 's/<h1>/   /; s/^Conectado/   Conectado/'
done
echo "--- acceso directo a :8081 desde la red (debe fallar)"
curl -s -m 3 "http://10.10.4.10:8081" > /dev/null && echo "   ABIERTO (revisar)" || echo "   Bloqueado: solo se entra por el proxy"
