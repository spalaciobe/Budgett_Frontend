# Budgett Frontend

Aplicacion de finanzas personales desarrollada en Flutter. Gestiona cuentas, transacciones, presupuestos, metas y tarjetas de credito, con autenticacion y datos en Supabase.

## Requisitos

- [Flutter](https://flutter.dev) (SDK ^3.6.1)
- [Supabase](https://supabase.com) (proyecto configurado o instancia local)

## Configuracion

1. Clona el repositorio y entra en el directorio:
   ```bash
   cd Budgett_Frontend
   ```

2. Instala dependencias:
   ```bash
   flutter pub get
   ```

3. Configura Supabase: edita `lib/core/app_constants.dart` con la URL y la clave anonima de tu proyecto Supabase. Por defecto apunta a una instancia local (`http://127.0.0.1:54321`).

4. (Opcional) Genera codigo para Riverpod:
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```

## Ejecucion

- **Web:** `flutter run -d chrome`
- **Windows:** `flutter run -d windows`
- **Android/iOS:** `flutter run` (con dispositivo o emulador conectado)

Para listar dispositivos disponibles: `flutter devices`.

## Estructura del proyecto

- `lib/core/` – Constantes, tema, utilidades (calendario colombiano, calculadora de tarjetas de credito).
- `lib/data/` – Modelos y repositorios (cuentas, transacciones, bancos, categorias, presupuestos, metas, etc.).
- `lib/presentation/` – Pantallas, widgets, navegacion (go_router), providers (Riverpod).

## Tecnologias

- **Flutter** – UI multiplataforma
- **Supabase** – Backend (auth y base de datos)
- **Riverpod** – Estado y inyeccion de dependencias
- **go_router** – Navegacion declarativa
- **fl_chart** – Graficos
- **google_fonts** – Tipografia
- **intl** – Formato de fechas y numeros

## Licencia

Proyecto privado (no publicado en pub.dev).
