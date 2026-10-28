# Despliegue en Ubuntu Server 22.04 con Coolify

Resultado final: la app en `https://mercado.tudominio.com`, con HTTPS
automático, PostgreSQL con datos persistentes y redespliegue con cada `git push`.

```
Internet ──443──▶ Coolify (Traefik, HTTPS) ──▶ web:80 (nginx) ──/api──▶ api:8080 ──▶ <uuid-de-la-base>:5432
```

Solo el servicio `web` recibe tráfico de fuera. `api` vive en la red interna
del compose. PostgreSQL es un recurso **PostgreSQL** aparte de Coolify y la API
lo alcanza por la red interna de Docker (`coolify`), nunca por la IP pública.

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

## 4. Crear los recursos en Coolify

1. **Projects → + Add → New Project** (por ejemplo, "Mercado Liebre").
2. **Base de datos:** dentro del proyecto, **+ New → Resource → PostgreSQL**.
   Arráncala y copia su **Postgres URL (internal)**. Tiene esta forma:
   `postgres://postgres:CLAVE@<uuid-del-recurso>:5432/postgres`.
   No actives *Make it publicly available*: la API no la necesita.
3. **App:** dentro del proyecto, **+ New → Resource**.
   - Repositorio público: **Public Repository** y pega la URL.
   - Privado: **Private Repository (with GitHub App)** o **(with Deploy Key)**.
   - **Build Pack:** `Docker Compose`.
   - **Branch:** `main`. **Docker Compose Location:** `/docker-compose.yml`.
   - Coolify lee el compose y muestra dos servicios: `api` y `web`.
4. Red: el compose ya une `api` a la red externa `coolify`, donde Coolify pone
   los recursos PostgreSQL; así la API resuelve `<uuid-del-recurso>`. Deja
   **Connect To Predefined Network** *desactivado*: esa opción renombra los
   servicios (`api` → `api-<uuid>`) y nginx dejaría de encontrar `api:8080`.
   Comprueba en qué red está la base con
   `docker inspect <uuid-del-recurso> --format '{{json .NetworkSettings.Networks}}'`;
   si no es `coolify`, cambia ese nombre al final de `docker-compose.yml`.

### 4.1 Variables de entorno

Pestaña **Environment Variables** del recurso de la app:

| Variable            | Valor                                                                 |
|---------------------|-----------------------------------------------------------------------|
| `DATABASE_URL`      | La *Postgres URL (internal)* del paso 2                               |
| `APP_SECRET_KEY`    | `openssl rand -hex 32`                                                |
| `ADMIN_CORREO`      | Correo del primer administrador                                       |
| `ADMIN_PASSWORD`    | Contraseña de ese administrador (8+ caracteres)                       |

Marca `DATABASE_URL`, `APP_SECRET_KEY` y `ADMIN_PASSWORD` como
**secretas** (no se mostrarán en logs).

**Correo** (verificación de cuentas nuevas y reportes de fallas):

| Variable          | Valor                                                       |
|-------------------|-------------------------------------------------------------|
| `SMTP_USUARIO`    | La cuenta de Zoho que envía, p. ej. `no.reply@mercadoliebre.shop` |
| `SMTP_PASSWORD`   | Su contraseña (**secreta**)                                  |
| `CORREO_REPORTES` | Buzón que recibe los reportes (por defecto `miguelsoto@mercadoliebre.shop`) |

`SMTP_HOST` (`smtppro.zoho.com`) y `SMTP_PUERTO` (`465`, SSL) ya tienen valor
por defecto. Sin `SMTP_USUARIO`/`SMTP_PASSWORD` la API arranca, avisa en los
logs y responde 503 al registrar el correo o enviar un reporte.

> **Nunca escribas `DATABASE_URL` en `docker-compose.yml`** ni en otro archivo
> del repositorio: lleva la contraseña. Si llegó a subirse a Git, cambia la
> contraseña en el recurso PostgreSQL y actualiza `DATABASE_URL` aquí.

### 4.2 Dominio

En la lista de servicios, abre **web → Settings → Domains** y escribe:

```
https://mercado.tudominio.com
```

No asignes dominio a `api` ni a la base. Coolify pedirá el certificado de
Let's Encrypt automáticamente.

### 4.3 Desplegar

Pulsa **Deploy**. El primer build tarda 5–10 minutos (descarga Flutter y Dart).
En **Logs** de `api` deberías ver:

```
Conectando con PostgreSQL…
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

Los servicios `api` y `web` y el recurso PostgreSQL deben aparecer
**Running (healthy)** en Coolify.

## 6. Respaldos

La base es un recurso PostgreSQL de Coolify: programa sus respaldos en la
pestaña **Backups** de ese recurso (local o S3).

Respaldo manual con `pg_dump` desde el servidor:

```bash
# El contenedor de la base se llama como el uuid del recurso:
docker exec <uuid-del-recurso> pg_dump -U postgres -d postgres -Fc > respaldo_$(date +%F).dump

# Restaurar
docker exec -i <uuid-del-recurso> pg_restore -U postgres -d postgres --clean < respaldo_2026-01-01.dump
```

Las fotos subidas viven en el volumen `datos_api`, que no entra en los
respaldos de la base. Respáldalo con
`docker run --rm -v NOMBRE_VOLUMEN:/d -v /root/respaldos:/r alpine tar czf /r/medios_$(date +%F).tgz -C /d .`

## 7. Problemas comunes

| Síntoma | Causa y solución |
|---------|------------------|
| Build de `web` termina en `Killed` o `exit code 137` | Falta memoria. Agrega swap (1.3) o usa un servidor de 4 GB. |
| `api` reinicia con `Falta DATABASE_URL` o `APP_SECRET_KEY debe tener…` | Faltan variables en Coolify (4.1). |
| Los correos no llegan; en logs `535 Authentication failed` | Revisa `SMTP_USUARIO`/`SMTP_PASSWORD`. Si la cuenta de Zoho tiene verificación en dos pasos, usa una *contraseña de aplicación*. |
| `api` no conecta: `password authentication failed` | La contraseña de `DATABASE_URL` no es la del recurso PostgreSQL. Cópiala de nuevo de su *Postgres URL (internal)*. |
| `api` no conecta: `Failed host lookup` | `api` y la base no comparten red de Docker. Revisa con `docker inspect` en qué red está la base (paso 4) y que `DATABASE_URL` use el host interno, no la IP pública. La API reintenta 10 veces (≈30 s) antes de reiniciarse. |
| La API ignora el `DATABASE_URL` nuevo | Un admin guardó otra conexión desde el panel (`/app/datos/conexion.json`, que tiene prioridad). Usa *Restaurar la del entorno* en el panel o borra ese archivo y reinicia `api`. |
| 502 Bad Gateway en `/api/...` y `/salud` | `api` no está sana o no escucha en 8080. Revisa sus logs; `web` reenvía a `api:8080`, así que `PORT` debe ser `8080`. |
| `Permission denied` al subir fotos tras actualizar | El volumen `datos_api` se creó cuando la API corría como root. Una sola vez: `docker run --rm -v NOMBRE_VOLUMEN_DATOS:/d alpine chown -R 10001 /d` y reinicia `api`. |
| La app muestra la versión vieja tras desplegar | Recarga forzada (Ctrl+Shift+R). `index.html` y `main.dart.js` se sirven con `no-cache`, así que basta una recarga. |
| El certificado HTTPS no se emite | El DNS aún no apunta al servidor, o los puertos 80/443 están cerrados. |

## 8. Actualizar

Haz `git push` (con webhook) o pulsa **Redeploy** en Coolify. La API aplica
`db/schema.sql` en cada arranque, así que los cambios de esquema escritos con
`IF NOT EXISTS` se aplican solos. Los volúmenes `pgdata` y `datos_api` se
conservan entre despliegues.
