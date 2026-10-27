# Despliegue en Ubuntu Server 22.04 con Coolify

Resultado final: la app en `https://mercado.tudominio.com`, con HTTPS
automático, PostgreSQL con datos persistentes y redespliegue con cada `git push`.

```
Internet ──443──▶ Coolify (Traefik, HTTPS) ──▶ web:80 (nginx) ──/api──▶ api:8080 ──▶ postgres:5432
```

Solo el servicio `web` recibe tráfico de fuera. `api` y `postgres` viven en la
red interna del compose.

---

## 1. Servidor

**Requisitos mínimos:** Ubuntu Server 22.04 LTS, 2 vCPU, **4 GB de RAM**, 30 GB
de disco, IP pública y un dominio (o subdominio) que puedas apuntar.

> La compilación de Flutter web usa ~2–3 GB de RAM. Con 2 GB el build se
> cae (`Killed` / código 137) a menos que agregues swap (paso 1.3).

### 1.1 Actualizar y crear un usuario con sudo

```bash
ssh root@IP_DEL_SERVIDOR
apt update && apt upgrade -y
adduser despliegue && usermod -aG sudo despliegue
```

### 1.2 Firewall

```bash
ufw allow OpenSSH
ufw allow 80/tcp      # HTTP (Let's Encrypt y redirección a HTTPS)
ufw allow 443/tcp     # HTTPS
ufw allow 8000/tcp    # Panel de Coolify (puedes cerrarlo después de poner un dominio al panel)
ufw allow 6001/tcp    # Coolify: tiempo real
ufw allow 6002/tcp    # Coolify: terminal web
ufw enable
```

> Docker publica puertos saltándose `ufw`. Por eso el `docker-compose.yml` de
> este repo **no publica** ningún puerto: PostgreSQL y la API nunca quedan
> expuestos a internet.

### 1.3 Swap (recomendado con 4 GB, obligatorio con 2 GB)

```bash
fallocate -l 4G /swapfile && chmod 600 /swapfile
mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

### 1.4 DNS

En tu proveedor de dominio crea un registro **A**:
`mercado.tudominio.com → IP_DEL_SERVIDOR`. Espera a que resuelva
(`ping mercado.tudominio.com`).

## 2. Instalar Coolify

```bash
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | sudo bash
```

El script instala Docker y Coolify. Al terminar abre `http://IP_DEL_SERVIDOR:8000`,
crea la cuenta de administrador de Coolify y elige **localhost** como servidor.

## 3. Subir el código a Git

Coolify despliega desde un repositorio Git (GitHub, GitLab, Gitea…).

```bash
git init
git add .
git commit -m "Mercado Liebre"
git remote add origin git@github.com:TU_USUARIO/mercado-liebre.git
git push -u origin main
```

Verifica que `.env` **no** aparezca en `git status` (está en `.gitignore`).

## 4. Crear el recurso en Coolify

1. **Projects → + Add → New Project** (por ejemplo, "Mercado Liebre").
2. Dentro del proyecto: **+ New → Resource**.
   - Repositorio público: **Public Repository** y pega la URL.
   - Privado: **Private Repository (with GitHub App)** o **(with Deploy Key)**.
3. **Build Pack:** `Docker Compose`.
4. **Branch:** `main`. **Docker Compose Location:** `/docker-compose.yml`.
5. Coolify lee el compose y muestra tres servicios: `postgres`, `api`, `web`.

### 4.1 Variables de entorno

Pestaña **Environment Variables** del recurso:

| Variable            | Valor                                                                 |
|---------------------|-----------------------------------------------------------------------|
| `POSTGRES_PASSWORD` | Solo letras y números, 24+ caracteres. Ej.: `openssl rand -hex 24`    |
| `APP_SECRET_KEY`    | `openssl rand -hex 32`                                                |
| `ADMIN_CORREO`      | Correo del primer administrador                                       |
| `ADMIN_PASSWORD`    | Contraseña de ese administrador (8+ caracteres)                       |

Marca `POSTGRES_PASSWORD`, `APP_SECRET_KEY` y `ADMIN_PASSWORD` como
**secretas** (no se mostrarán en logs).

> **No cambies `POSTGRES_PASSWORD` después del primer despliegue.** PostgreSQL
> solo la lee al crear el volumen; si la cambias, la API no podrá entrar.
> Para rotarla, cámbiala dentro de la base (`ALTER USER mercado PASSWORD '…'`)
> y luego en Coolify.

### 4.2 Dominio

En la lista de servicios, abre **web → Settings → Domains** y escribe:

```
https://mercado.tudominio.com
```

No asignes dominio a `api` ni a `postgres`. Coolify pedirá el certificado de
Let's Encrypt automáticamente.

### 4.3 Desplegar

Pulsa **Deploy**. El primer build tarda 5–10 minutos (descarga Flutter y Dart).
En **Logs** de `api` deberías ver:

```
Aplicando esquema de PostgreSQL…
Esquema listo.
Comprobando la cuenta de administrador…
API de Mercado Liebre en el puerto 8080.
```

Abre `https://mercado.tudominio.com` y entra con `ADMIN_CORREO`/`ADMIN_PASSWORD`.

### 4.4 Redespliegue automático (opcional)

En **Webhooks** del recurso copia la URL y agrégala en GitHub
(**Settings → Webhooks**), o activa *Automatic Deployment* si usas la GitHub
App. Cada `git push` a `main` volverá a desplegar.

## 5. Verificar

```bash
curl https://mercado.tudominio.com/salud          # {"estado":"ok"}
curl https://mercado.tudominio.com/api/apariencia  # JSON con el título
```

Los tres servicios deben aparecer **Running (healthy)** en Coolify.

## 6. Respaldos de la base

El PostgreSQL de este compose no es una "base administrada" de Coolify, así
que el respaldo se hace con `pg_dump` desde el servidor:

```bash
# Nombre real del contenedor (Coolify le agrega un sufijo):
docker ps --filter "name=postgres" --format "{{.Names}}"

# Respaldo manual
docker exec NOMBRE_CONTENEDOR pg_dump -U mercado -d mercado_liebre -Fc > respaldo_$(date +%F).dump

# Restaurar
docker exec -i NOMBRE_CONTENEDOR pg_restore -U mercado -d mercado_liebre --clean < respaldo_2026-01-01.dump
```

Respaldo diario a las 3 a. m. guardando 14 días (`crontab -e` como root):

```cron
0 3 * * * C=$(docker ps -qf "name=postgres" | head -1) && docker exec $C pg_dump -U mercado -d mercado_liebre -Fc > /root/respaldos/mercado_$(date +\%F).dump && find /root/respaldos -name '*.dump' -mtime +14 -delete
```

(Crea antes la carpeta: `mkdir -p /root/respaldos`.) Las fotos subidas viven
en el volumen `datos_api`; respáldalo igual con `docker run --rm -v NOMBRE_VOLUMEN:/d -v /root/respaldos:/r alpine tar czf /r/medios_$(date +%F).tgz -C /d .`

Si prefieres respaldos desde el panel de Coolify (con S3), crea la base como
recurso **PostgreSQL** de Coolify, borra el servicio `postgres` del compose y
cambia `DATABASE_URL` en `api` por la URL interna que Coolify te muestre.

## 7. Problemas comunes

| Síntoma | Causa y solución |
|---------|------------------|
| Build de `web` termina en `Killed` o `exit code 137` | Falta memoria. Agrega swap (1.3) o usa un servidor de 4 GB. |
| `api` reinicia con `Falta DATABASE_URL` o `APP_SECRET_KEY debe tener…` | Faltan variables en Coolify (4.1). |
| `api` no conecta: `password authentication failed` | Cambiaste `POSTGRES_PASSWORD` después de crear el volumen. Ver nota en 4.1. |
| 502 Bad Gateway en `/api/...` | `api` no está sana. Revisa sus logs; `web` reenvía a `api:8080`. |
| `Permission denied` al subir fotos tras actualizar | El volumen `datos_api` se creó cuando la API corría como root. Una sola vez: `docker run --rm -v NOMBRE_VOLUMEN_DATOS:/d alpine chown -R 10001 /d` y reinicia `api`. |
| La app muestra la versión vieja tras desplegar | Recarga forzada (Ctrl+Shift+R). `index.html` y `main.dart.js` se sirven con `no-cache`, así que basta una recarga. |
| El certificado HTTPS no se emite | El DNS aún no apunta al servidor, o los puertos 80/443 están cerrados. |

## 8. Actualizar

Haz `git push` (con webhook) o pulsa **Redeploy** en Coolify. La API aplica
`db/schema.sql` en cada arranque, así que los cambios de esquema escritos con
`IF NOT EXISTS` se aplican solos. Los volúmenes `pgdata` y `datos_api` se
conservan entre despliegues.
