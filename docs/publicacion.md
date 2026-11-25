# Publicar Drago (APK y web)

Cada cambio en la rama principal ejecuta `.github/workflows/build.yml`, que:

1. corre el análisis y las pruebas;
2. compila el **APK** y lo publica en la versión **android-latest** (enlace fijo);
3. compila la **versión web** y la publica en **GitHub Pages**.

También se puede lanzar a mano: **Actions → Compilar y publicar → Run workflow**.

## Configuración (una sola vez)

### 1. Activar GitHub Pages

**Settings → Pages → Build and deployment → Source: GitHub Actions.**

La app web queda en `https://darkhmdda.github.io/Drago/`.
GitHub Pages en repositorios **privados** requiere un plan de pago; en uno público es gratis.

### 2. Llave de firma del APK

Android solo deja actualizar una app si la nueva versión está firmada con la misma llave. En
**Settings → Secrets and variables → Actions → New repository secret** crea:

| Nombre | Valor |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | la llave en base64 |
| `ANDROID_KEYSTORE_PASSWORD` | su contraseña |

Guarda una copia de la llave fuera del repositorio: si se pierde, habrá que desinstalar la app para
instalar versiones firmadas con una llave nueva (los datos sincronizados vuelven al iniciar sesión).
Sin estos secretos el APK se firma con una llave temporal y cada versión exige desinstalar la anterior.

### 3. Supabase

En **Authentication → URL Configuration**:

- **Site URL**: `https://darkhmdda.github.io/Drago/`
- **Redirect URLs**: agrega `https://darkhmdda.github.io/Drago/**`

Así los enlaces de confirmación de correo y de «Olvidé mi contraseña» abren la app web.

## Instalar en Android

1. Desde el teléfono abre
   `https://github.com/darkhmdda/Drago/releases/download/android-latest/drago.apk`
   (o la página **Releases** del repositorio) y descarga **drago.apk**.
2. Ábrelo y permite «instalar apps de fuentes desconocidas» para el navegador cuando lo pida.
3. Para actualizar, repite: se instala encima conservando los datos.
