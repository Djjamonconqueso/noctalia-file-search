# Fuente local de plugins para Noctalia

Esta carpeta es una fuente local para Noctalia. Añádela como fuente de tipo `path`:

```text
~/src/noctalia-ollama-search
```

No selecciones la subcarpeta `ollama-file-search`: Noctalia lee `catalog.toml` en la raíz y encuentra cada plugin dentro de una subcarpeta con el nombre indicado por el ID. Después activa **File Search** en Settings → Plugins.

El plugin está en [`ollama-file-search/`](ollama-file-search/README.md). Usa el CLI y el índice local de DigUp. El binario de DigUp no se incluye aquí: consulta allí cómo instalarlo desde sus publicaciones oficiales y cómo indicar la ruta de su helper `digup`.
