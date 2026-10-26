#!/bin/bash
# Script del Equipo 4 - Administracion de servidores
# Crea la base de datos, el usuario de MySQL, una tabla por pagina
# y una pagina PHP en cada sitio que demuestra la conexion por el puerto 3306.
#
# Uso (en la VM):  bash instalar.sh

set -e

echo "== 1. Instalando PHP y su conector a MySQL =="
sudo apt install -y php libapache2-mod-php php-mysql

echo "== 2. Creando base de datos, usuario y tablas =="
sudo mysql <<'SQL'
CREATE DATABASE IF NOT EXISTS equipo4;

CREATE USER IF NOT EXISTS 'equipo4'@'localhost' IDENTIFIED BY 'Equipo4.2026';
CREATE USER IF NOT EXISTS 'equipo4'@'127.0.0.1' IDENTIFIED BY 'Equipo4.2026';
GRANT ALL PRIVILEGES ON equipo4.* TO 'equipo4'@'localhost';
GRANT ALL PRIVILEGES ON equipo4.* TO 'equipo4'@'127.0.0.1';
FLUSH PRIVILEGES;

USE equipo4;

DROP TABLE IF EXISTS usuarios_pagina1, usuarios_pagina2, usuarios_pagina3, usuarios_pagina4;

CREATE TABLE usuarios_pagina1 (
  id INT AUTO_INCREMENT PRIMARY KEY,
  usuario VARCHAR(50) NOT NULL,
  contrasena VARCHAR(64) NOT NULL
);
CREATE TABLE usuarios_pagina2 LIKE usuarios_pagina1;
CREATE TABLE usuarios_pagina3 LIKE usuarios_pagina1;
CREATE TABLE usuarios_pagina4 LIKE usuarios_pagina1;

INSERT INTO usuarios_pagina1 (usuario, contrasena) VALUES ('ana',   SHA2('1234',256)), ('luis',  SHA2('abcd',256));
INSERT INTO usuarios_pagina2 (usuario, contrasena) VALUES ('maria', SHA2('1234',256)), ('pedro', SHA2('abcd',256));
INSERT INTO usuarios_pagina3 (usuario, contrasena) VALUES ('sofia', SHA2('1234',256)), ('jorge', SHA2('abcd',256));
INSERT INTO usuarios_pagina4 (usuario, contrasena) VALUES ('laura', SHA2('1234',256)), ('diego', SHA2('abcd',256));
SQL

echo "== 3. Creando la pagina usuarios.php en cada sitio =="
PLANTILLA=$(cat <<'PHP'
<?php
$c = new mysqli('127.0.0.1', 'equipo4', 'Equipo4.2026', 'equipo4', 3306);
if ($c->connect_error) die('Error de conexion: ' . $c->connect_error);
echo '<h1>Conectado a MySQL - puerto 3306</h1>';
echo '<h2>Tabla: TABLA</h2>';
$r = $c->query('SELECT id, usuario, contrasena FROM TABLA');
echo '<table border="1" cellpadding="6"><tr><th>ID</th><th>Usuario</th><th>Contrasena (SHA-256)</th></tr>';
while ($f = $r->fetch_assoc()) {
  echo '<tr><td>' . $f['id'] . '</td><td>' . $f['usuario'] . '</td><td>' . $f['contrasena'] . '</td></tr>';
}
echo '</table>';
$c->close();
?>
PHP
)

# carpeta:tabla  (paginas = pagina2, paginas2 = pagina4)
for PAR in "pagina1:usuarios_pagina1" "paginas:usuarios_pagina2" "pagina3:usuarios_pagina3" "paginas2:usuarios_pagina4"; do
  CARPETA="${PAR%%:*}"
  TABLA="${PAR##*:}"
  echo "${PLANTILLA//TABLA/$TABLA}" | sudo tee "/var/www/$CARPETA/usuarios.php" > /dev/null
  echo "   /var/www/$CARPETA/usuarios.php -> $TABLA"
done

echo "== 4. Reiniciando Apache =="
sudo systemctl restart apache2

echo "== 5. Probando las 4 paginas =="
for URL in "https://localhost/usuarios.php" "https://localhost:8002/usuarios.php" "https://localhost:8003/usuarios.php" "https://localhost:8004/usuarios.php"; do
  echo "--- $URL"
  curl -sk "$URL" | grep -o '<h[12]>[^<]*' | sed 's/<h[12]>/   /'
done

echo ""
echo "Listo. Abre en el navegador:"
echo "   https://10.1.213.63/usuarios.php        (pagina1)"
echo "   https://10.1.213.63:8002/usuarios.php   (pagina2)"
echo "   https://10.1.213.63:8003/usuarios.php   (pagina4)"
echo "   https://10.1.213.63:8004/usuarios.php   (pagina3)"
