# Revisiones con el cliente — puesta en marcha

Comentarios, historial, versiones y aprobaciones de cada diseño. Los datos
viven en Supabase (gratis). El visor sigue en GitHub Pages como hasta ahora.

Mientras no se complete el paso 4, los visores funcionan exactamente igual
que antes.

---

## Cómo funciona

**El cliente**, en su enlace (`ver.html?c=…`), pulsa **Comentarios** y ve el
historial del diseño abierto. Puede:

- escribir lo que cambiaría y **adjuntar** imágenes, PDF o cualquier archivo
  de hasta 25 MB (también pegando una captura con Ctrl+V o soltando archivos
  sobre el panel);
- **aprobar** la versión que está viendo.

En la tira de diseños, cada uno lleva su estado: *En revisión*, *Cambios
pedidos* o *Aprobado vN*.

**Tú**, en el visor interno, tienes el botón **Revisiones** arriba a la
derecha, con el número de peticiones pendientes. Ahí:

- cada petición del cliente se **acepta** (con una nota opcional) o se
  **rechaza** (con el motivo, que el cliente ve);
- se le **responde**, también con adjuntos;
- los filtros *Pendientes · Todos · Aprobados* ordenan el trabajo.

**Versiones.** Si subes a un cliente un diseño con el **mismo título y el
mismo modelo** que uno que ya tiene, el visor pregunta si es una versión
nueva. Si dices que sí, lo sustituye (v2, v3…), conserva el historial y deja
en él la vista previa de la versión. El cliente puede volver a aprobar o
pedir cambios sobre la nueva.

**Aviso por correo.** Cada comentario o aprobación del cliente te llega por
correo con enlace directo a Revisiones.

---

## 1. Crear el proyecto en Supabase (5 min)

1. Entra en <https://supabase.com> › **Start your project** y crea la cuenta.
2. **New project**. Nombre: `visor-rumm`. Región: **West EU (Ireland)** o
   **Central EU (Frankfurt)**. Apunta la contraseña de la base de datos (no
   la necesitarás en el visor, pero guárdala).
3. Espera a que termine de crearse (un par de minutos).

## 2. Crear tu usuario del estudio

1. **Authentication › Users › Add user › Create new user**.
2. Tu correo y una contraseña. Marca **Auto Confirm User**.
3. **Authentication › Sign In / Providers › Email**: desactiva
   **Allow new users to sign up**. Así nadie más puede crearse una cuenta.
   (Aunque alguien lo hiciera, no vería nada: solo entran los correos de la
   tabla `equipo` del paso 4.)

## 3. Cuenta de Resend para los avisos (3 min)

1. Entra en <https://resend.com> y crea la cuenta **con el mismo correo en el
   que quieres recibir los avisos**. Sin verificar un dominio propio, Resend
   solo deja enviar a ese correo, que es justo lo que hace falta.
2. **API Keys › Create API Key**. Permiso: *Sending access*. Copia la clave
   (empieza por `re_`).

Si te saltas este paso, todo funciona igual salvo el correo.

## 4. Crear las tablas

1. Abre `supabase/esquema.sql` con el Bloc de notas.
2. Al final del archivo, cambia los tres valores marcados con `<<<`:
   - el correo con el que entrarás al visor (el del paso 2);
   - el correo de aviso (el de Resend);
   - la clave de Resend.
3. En Supabase: **SQL Editor › New query**, pega el archivo entero y pulsa
   **Run**. Debe terminar con *Success. No rows returned*.

Se puede volver a ejecutar cuando quieras (por ejemplo, para cambiar la clave
de Resend): no borra nada.

## 5. Conectar el visor

1. En Supabase: **Project Settings › API** (o **Data API**). Copia:
   - **Project URL** (`https://xxxxxxxx.supabase.co`)
   - la clave **anon public** (una cadena larga que empieza por `eyJ`).
     Esta clave es pública por diseño: lo que protege los datos son las
     reglas del paso 4. **No uses nunca la `service_role`.**
2. Abre `revisiones.js` y rellena las dos primeras líneas de `REV_CONFIG`:

   ```js
   url:'https://xxxxxxxx.supabase.co',
   anonKey:'eyJhbGciOi…',
   ```

## 6. Subir a GitHub

En <https://github.com/dasogu92/VISOR3D> › **Add file › Upload files**, arrastra:

- `index.html`
- `ver.html`
- `revisiones.js` (nuevo, en la raíz, junto a los otros dos)
- la carpeta `supabase` (opcional: es documentación, el visor no la usa)

**Commit changes**. GitHub Pages tarda uno o dos minutos en publicar.

## 7. Primera prueba

1. Abre el visor interno. Arriba a la derecha aparece **Revisiones**. Pulsa y
   entra con el usuario del paso 2.
2. En **Clientes**, pulsa **Publicar** en un cliente que ya exista. Esto lo da
   de alta en Supabase: **los enlaces ya enviados no admiten comentarios
   hasta que se vuelvan a publicar una vez.**
3. Abre su enlace en otra ventana, pulsa **Comentarios**, escribe algo y
   adjunta una imagen.
4. Te llega el correo, y en **Revisiones** aparece como pendiente.
   Acéptalo o recházalo y recarga el enlace del cliente: verá la decisión.

---

## Pedidos nuevos (pedido.html)

Un formulario público para que el cliente te pida un diseño:
`https://dasogu92.github.io/VISOR3D/pedido.html`. En **Revisiones › Enlace
de pedidos** se copia para ponerlo en la web, en Instagram o en WhatsApp.

El cliente rellena sus datos, lo que corre (asfalto, trail…), las prendas
del catálogo con unidades, los colores que le gustan, su idea y sus
referencias (logos, imágenes, PDF). Al enviarlo:

- se crea el pedido con número **AAAA-NNNN** (2026-0001, 2026-0002…);
- el cliente recibe **su enlace privado**, que muestra «Pedido recibido»
  hasta que publiques el primer diseño;
- te llega un correo (si Resend está configurado) y el pedido aparece en
  **Revisiones › Pedidos** como *Nuevo*.

En el pedido, **Diseñar para este pedido** crea el cliente en el visor con
ese mismo enlace y abre la prenda. Subes el diseño, pulsas **Subir a enlace
privado** (el nombre del cliente ya viene puesto) y el cliente lo ve en el
enlace que ya tiene. El pedido pasa solo a *Enviado* al publicar y a
*Aprobado* cuando el cliente lo aprueba.

Requiere ejecutar `supabase/pedidos.sql` una vez en el SQL Editor, después
de `esquema.sql`.

Para que el cliente reciba un correo automático cuando su diseño esté listo
hace falta verificar un dominio propio en Resend. Mientras tanto, mándale
el enlace por WhatsApp o correo (botón **Copiar enlace del cliente**).

---

## Privacidad

Igual que los enlaces: el historial y los adjuntos solo los ve quien tiene el
enlace del cliente. Un cliente no puede leer el de otro ni listar archivos.
Los adjuntos se guardan en una carpeta con el token del cliente; quien tenga
la dirección exacta de un archivo puede abrirlo, igual que pasa con los
diseños publicados en GitHub.

## Límites del plan gratuito de Supabase

- 500 MB de base de datos: millones de comentarios.
- 1 GB de archivos adjuntos. Con capturas y PDF normales da para mucho. Si se
  llena, se borran adjuntos antiguos en **Storage › adjuntos**.
- El proyecto **se pausa si pasa 7 días sin ninguna actividad**. Se reactiva
  desde el panel de Supabase con un clic. Con clientes comentando no pasa.

Resend gratis: 100 correos al día y 3000 al mes.

## Si algo falla

| Síntoma | Causa |
|---|---|
| No aparece el botón Revisiones | `revisiones.js` sin subir, o `url`/`anonKey` vacíos |
| «Tu correo no está en la tabla equipo» | Añádelo: `insert into equipo values ('tu@correo');` en SQL Editor |
| El cliente ve «Enlace no válido» al enviar | Ese cliente no se ha vuelto a publicar desde que se montó esto |
| No llegan los correos | Revisa la clave en **Table Editor › ajustes**. El destino tiene que ser el correo de tu cuenta de Resend |
| Los correos van a spam | Normal con el remitente de pruebas `onboarding@resend.dev`. Márcalo como «no es spam» o verifica un dominio en Resend |
