# Usuarios compartidos BIA: cambio preparado, pendiente de autorización de producción

## Problema y comportamiento resultante

Los tres sistemas usan el mismo proyecto Supabase, pero hoy administran cuentas por tres caminos distintos. Control de Tiempos crea cuentas desde `admin-users`; Devoluciones envía invitaciones SMTP; Contenedores usa `signUp` y `user_profiles`.

Esta propuesta usa `auth.users` para identidad, `usuarios_sedes` para permisos y estado por sede, y `admin-users` para crear/asignar cuentas en los tres sistemas. La tabla `usuarios` conserva sus IDs numéricos históricos para Devoluciones y se vincula automáticamente con la cuenta Auth. No se copian contraseñas entre tablas.

Las cuentas nuevas reciben una contraseña aleatoria temporal, confirmación administrativa y cambio obligatorio al ingresar. Las cuentas existentes reutilizan su contraseña. No se requiere correo SMTP para crear cuentas. Solo administradores autenticados y autorizados en la sede pueden crear/asignar accesos.

## Migración y alcance

- `database/usuarios_compartidos.sql`: conserva las asignaciones actuales de `usuarios_sedes` y agrega los perfiles de Contenedores que falten, sin sobrescribir asignaciones existentes.
- Agrega el rol `operador`, mantiene `admin` y `consulta`, sincroniza la identidad histórica de Devoluciones y publica consultas/ediciones de usuarios con control de sede.
- Contenedores utiliza las mismas asignaciones para su listado, validación del perfil y políticas RLS. Se retira la escritura directa a su tabla de perfiles antigua, que permanece como archivo compatible para conservar los datos existentes.
- Activar/desactivar un acceso se refleja en las tres aplicaciones para esa sede. No se eliminan usuarios ni registros operativos existentes. Las cuentas con otras sedes activas conservan esas sedes.
- En Control de Tiempos se conserva el comportamiento actual: `admin` administra la operación; `consulta` y `operador` no reciben privilegios administrativos por este cambio.
- Las cuentas antiguas sin vínculo a Auth no se enlazan por nombre ni se les asignan contraseñas; solo se vincula una coincidencia de correo inequívoca. Se comprobó que no existen conflictos de correo con otra cuenta Auth.

## Archivos de despliegue

1. SQL: `database/usuarios_compartidos.sql`.
2. Servidor: `supabase/functions/admin-users/index.ts`; conservar `verify_jwt=true`.
3. Compatibilidad de Devoluciones: `supabase/functions/devoluciones-usuarios/index.ts`; conservar `verify_jwt=true`. Delega en `admin-users` con el token original; no crea otro método.
4. Frontend Contenedores: archivos del PR.
5. Frontend Devoluciones: PR correspondiente, también conservado en `devoluciones.patch`.
6. Control de Tiempos: aplicar `control-tiempos.patch` desde la raíz de su repositorio con `git apply --check` y `git apply`. Falta permiso de escritura a ese repositorio en la conexión actual.

Se requiere un corte coordinado: aplicar SQL, desplegar funciones y publicar frontends en la misma ventana. Durante el cambio puede haber errores de validación/listado de perfiles hasta terminar la publicación. La migración está en una transacción: si una instrucción falla no deja cambios parciales. Las funciones de sincronización se alojan en un esquema privado y no son ejecutables por clientes.

## Validación realizada sin modificar producción

Pruebas con PostgreSQL local (PGlite 0.3.14): migración repetible, conservación de identidad/roles, vinculación de perfiles previos, desactivación compartida, restricciones por sede, escritura de operador, rechazo de consulta/anon y edición rechazada a no administradores.

Pruebas del servidor con TypeScript 5.9.3: autorización, credencial temporal, cambio obligatorio, reutilización de cuenta existente y eliminación de una cuenta recién creada si falla su asignación. No envían correos ni crean cuentas reales.

Prueba del componente de Contenedores: sin usuario autenticado no renderiza formularios operativos. La pantalla de acceso, el cierre de sesión y el favicon de Contenedores ya se publicaron separadamente.

Comandos desde la raíz de este repositorio, con las dependencias de pruebas disponibles:

```
node tests/session_gate.cjs
node tests/shared_identity.cjs
node tests/admin_users.cjs
```

No se pudo ejecutar una prueba visual de navegador: la descarga del navegador de Playwright no estuvo disponible. Antes de cerrar el despliegue, probar una cuenta temporal desde cada plataforma y verificar su aparición en las otras, su sede, el cambio inicial de contraseña y la denegación de acceso al cerrar sesión.

## Estado

La revisión automática rechazó ejecutar la migración de producción por el alcance de los cambios de identidad/RLS. No se ejecutó. Las funciones nuevas tampoco se desplegaron porque dependen de la migración. Este PR se deja para revisión y autorización expresa del cambio descrito.
