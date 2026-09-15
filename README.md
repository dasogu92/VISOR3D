# VISOR 3D — repositorio

Visor web de prendas con estampación en vivo, publicado en GitHub Pages.

## Estructura

```
/
├── index.html            visor interno (el tuyo)
├── ver.html              visor de cliente
├── catalogo.json         índice de modelos
├── generar-catalogo.js   regenera catalogo.json desde models/
├── models/
│   ├── 0917/
│   │   ├── manifest.json
│   │   ├── captura1.png
│   │   └── …geometría, config y mapas
│   └── 1756/…
└── c/                    carpetas de cliente (una por enlace)
    └── a7f3k9x2p1/
        ├── galeria.json
        ├── diseno-1.jpg
        └── preview-1.png
```

## Publicar

1. Crea un repositorio en GitHub y sube todo esto.
2. En el repositorio: **Settings → Pages → Source: Deploy from a branch**, rama `main`, carpeta `/ (root)`.
3. En un par de minutos tendrás `https://TUUSUARIO.github.io/NOMBREREPO/`.

El visor interno queda en la raíz. Si no quieres que sea la portada, renombra
`index.html` a `visor.html`.

## Añadir modelos

Copia la carpeta del modelo dentro de `models/` y ejecuta:

```
node generar-catalogo.js
```

Sube los cambios. El visor solo muestra los modelos que existen de verdad.

## Entregar diseños a un cliente

1. En el visor interno, abre un modelo y sube el JPG del diseño.
2. Coloca la cámara como quieras que la vea el cliente.
3. Escribe un título y pulsa **Añadir a galería**. Repite con los diseños que hagan falta.
4. Pulsa **Ver galería → EXPORTAR**. Se descarga un ZIP y te muestra el enlace.
5. Descomprime el ZIP en la raíz del repositorio: crea `c/TOKEN/`.
6. Sube los cambios y manda el enlace.

El enlace tiene la forma:

```
https://TUUSUARIO.github.io/NOMBREREPO/ver.html?c=TOKEN
```

## Sobre la privacidad de los enlaces

El nombre de la carpeta son 12 caracteres aleatorios, imposible de acertar
probando. No existe ningún índice que liste las carpetas de cliente, así que
desde una galería no se puede llegar a otra.

Ahora bien, el repositorio es público y los archivos están ahí: cualquiera
con el enlace entra, y quien conozca el nombre de una carpeta la ve. Sirve
para que un cliente no vea lo de otro por accidente, no para proteger algo
confidencial. Si algún día hace falta control de acceso real, hay que pasar
a un servidor que valide permisos.

## Formatos de modelo

- **legacy**: JSON antiguo de Three.js exportado desde 3ds Max. Cada carpeta
  lleva `manifest.json` con las secciones `exterior` e `interior`, cada una
  con su `config` de materiales y su `geometry`.
- **glb**: `manifest.json` con `{"format":"glb","file":"modelo.glb"}`.
