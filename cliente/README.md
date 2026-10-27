# Cliente Flutter de Mercado Liebre

App para web, Android, iOS y Windows. Habla únicamente con la API HTTP de
`../servidor`; no contiene host, usuario ni contraseña de PostgreSQL.

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8080
flutter test
```

En el emulador de Android usa `http://10.0.2.2:8080`. En producción (Docker)
se compila con `API_BASE_URL=same`: la app llama a `/api` en su propio dominio.

Estructura, convenciones y recetas: [../AGENTS.md](../AGENTS.md).
