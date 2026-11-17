#!/bin/bash
# Equipo 4 - Administracion de Servidores
# Monta 3 paginas web con base de datos en la VM 104 (10.10.4.10),
# listas para publicarse a traves del proxy inverso.
#
# Uso:
#   bash instalar2.sh                 -> abre los puertos 8081-8083 a toda la red
#   bash instalar2.sh 10.10.X.X       -> solo deja entrar al proxy inverso (recomendado)
#
# La contrasena de MySQL se pide al correr el script; no queda escrita en GitHub.

set -e
PROXY_IP="$1"

read -s -p "Escribe la contrasena que tendra el usuario de MySQL 'equipo4': " DBPASS; echo
[ -z "$DBPASS" ] && { echo "La contrasena no puede ir vacia."; exit 1; }

echo "== 1. Instalando Apache, PHP y MySQL =="
sudo apt update
sudo apt install -y apache2 php libapache2-mod-php php-mysql mysql-server

echo "== 2. Base de datos, usuario y tablas =="
sudo mysql <<SQL
CREATE DATABASE IF NOT EXISTS equipo4;
CREATE USER IF NOT EXISTS 'equipo4'@'localhost' IDENTIFIED BY '${DBPASS}';
CREATE USER IF NOT EXISTS 'equipo4'@'127.0.0.1' IDENTIFIED BY '${DBPASS}';
ALTER USER 'equipo4'@'localhost' IDENTIFIED BY '${DBPASS}';
ALTER USER 'equipo4'@'127.0.0.1' IDENTIFIED BY '${DBPASS}';
GRANT ALL PRIVILEGES ON equipo4.* TO 'equipo4'@'localhost';
GRANT ALL PRIVILEGES ON equipo4.* TO 'equipo4'@'127.0.0.1';
FLUSH PRIVILEGES;
USE equipo4;
CREATE TABLE IF NOT EXISTS usuarios_pagina1 (
  id INT AUTO_INCREMENT PRIMARY KEY,
  usuario VARCHAR(50) NOT NULL,
  contrasena VARCHAR(255) NOT NULL,
  creado TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS usuarios_pagina2 LIKE usuarios_pagina1;
CREATE TABLE IF NOT EXISTS usuarios_pagina3 LIKE usuarios_pagina1;
SQL

echo "== 3. Credenciales fuera de /var/www (solo las lee Apache) =="
sudo mkdir -p /etc/equipo4
printf "<?php\nreturn ['host'=>'127.0.0.1','port'=>3306,'user'=>'equipo4','pass'=>'%s','db'=>'equipo4'];\n" "$DBPASS" | sudo tee /etc/equipo4/db.php > /dev/null
sudo chown root:www-data /etc/equipo4/db.php
sudo chmod 640 /etc/equipo4/db.php

echo "== 4. Paginas PHP =="
crear_pagina () {
  local N="$1" COLOR="$2"
  sudo mkdir -p "/var/www/equipo4-pagina$N"
  sudo tee "/var/www/equipo4-pagina$N/index.php" > /dev/null <<PHP
<?php
\$cfg = require '/etc/equipo4/db.php';
\$c = new mysqli(\$cfg['host'], \$cfg['user'], \$cfg['pass'], \$cfg['db'], \$cfg['port']);
if (\$c->connect_error) { http_response_code(500); die('Error de conexion a MySQL'); }
\$msg = '';
if (\$_SERVER['REQUEST_METHOD'] === 'POST' && !empty(\$_POST['usuario']) && !empty(\$_POST['contrasena'])) {
  \$st = \$c->prepare('INSERT INTO usuarios_pagina$N (usuario, contrasena) VALUES (?, ?)');
  \$hash = password_hash(\$_POST['contrasena'], PASSWORD_DEFAULT);
  \$st->bind_param('ss', \$_POST['usuario'], \$hash);
  \$st->execute();
  \$msg = 'Usuario registrado.';
}
\$r = \$c->query('SELECT id, usuario, creado FROM usuarios_pagina$N ORDER BY id');
\$ip = \$_SERVER['HTTP_X_FORWARDED_FOR'] ?? \$_SERVER['REMOTE_ADDR'];
?>
<!doctype html>
<html lang="es"><head><meta charset="utf-8"><title>Equipo 4 - Pagina $N</title>
<style>body{font-family:sans-serif;max-width:720px;margin:40px auto;padding:0 16px}
h1{color:$COLOR}table{border-collapse:collapse;width:100%}td,th{border:1px solid #ccc;padding:6px}
th{background:$COLOR;color:#fff}input,button{padding:6px;margin:4px 0}</style></head>
<body>
<h1>Equipo 4 - Pagina $N</h1>
<p><b>Conectado a MySQL</b> (base equipo4, tabla usuarios_pagina$N, puerto 3306).</p>
<p>Servidor: 10.10.4.10 &middot; Visitante: <?= htmlspecialchars(\$ip) ?></p>
<form method="post">
  <input name="usuario" placeholder="Usuario" required>
  <input name="contrasena" type="password" placeholder="Contrasena" required>
  <button>Registrar</button> <?= \$msg ?>
</form>
<table><tr><th>ID</th><th>Usuario</th><th>Registrado</th></tr>
<?php while (\$f = \$r->fetch_assoc()): ?>
<tr><td><?= \$f['id'] ?></td><td><?= htmlspecialchars(\$f['usuario']) ?></td><td><?= \$f['creado'] ?></td></tr>
<?php endwhile; ?>
</table>
</body></html>
PHP
  sudo chmod 755 "/var/www/equipo4-pagina$N"
}
crear_pagina 1 "#2E74B5"
crear_pagina 2 "#2E8B57"
crear_pagina 3 "#B5462E"

echo "== 5. Sitios de Apache en los puertos 8081, 8082 y 8083 =="
for N in 1 2 3; do
  PUERTO=$((8080 + N))
  grep -q "^Listen $PUERTO" /etc/apache2/ports.conf || echo "Listen $PUERTO" | sudo tee -a /etc/apache2/ports.conf > /dev/null
  sudo tee "/etc/apache2/sites-available/equipo4-pagina$N.conf" > /dev/null <<CONF
<VirtualHost *:$PUERTO>
    DocumentRoot /var/www/equipo4-pagina$N
    DirectoryIndex index.php
    ErrorLog \${APACHE_LOG_DIR}/equipo4-pagina$N-error.log
    CustomLog \${APACHE_LOG_DIR}/equipo4-pagina$N-access.log combined
</VirtualHost>
CONF
  sudo a2ensite "equipo4-pagina$N.conf" > /dev/null
done
sudo apache2ctl configtest
sudo systemctl restart apache2
sudo systemctl enable apache2 mysql > /dev/null

echo "== 6. Firewall (UFW) =="
sudo ufw allow 22/tcp > /dev/null
for PUERTO in 8081 8082 8083; do
  if [ -n "$PROXY_IP" ]; then
    sudo ufw allow from "$PROXY_IP" to any port "$PUERTO" proto tcp > /dev/null
  else
    sudo ufw allow "$PUERTO"/tcp > /dev/null
  fi
done
sudo ufw --force enable > /dev/null
sudo ufw status

echo "== 7. Prueba local =="
for PUERTO in 8081 8082 8083; do
  echo "--- http://localhost:$PUERTO"
  curl -s "http://localhost:$PUERTO" | grep -o '<h1>[^<]*\|Conectado a MySQL' | sed 's/<h1>/   /; s/^Conectado/   Conectado/'
done
echo ""
echo "Listo. Falta configurar el proxy inverso para que apunte a:"
echo "   http://10.10.4.10:8081   (pagina 1)"
echo "   http://10.10.4.10:8082   (pagina 2)"
echo "   http://10.10.4.10:8083   (pagina 3)"
