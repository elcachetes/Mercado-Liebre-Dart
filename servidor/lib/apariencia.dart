/// Claves que el administrador puede cambiar, con su valor inicial.
///
/// Los anuncios ya no viven aquí: tienen su propia tabla (`anuncios`) y
/// rutas (`/api/anuncios`, `/api/admin/anuncios/...`).
const Map<String, String> aparienciaPredeterminada = {
  'titulo': 'Mercado Liebre',
  'menuInicio': 'Inicio',
  'menuBusqueda': 'Búsqueda',
  'menuMapa': 'Mapa',
  'menuPerfil': 'Perfil',
  'iconoInicio': 'home',
  'iconoBusqueda': 'search',
  'iconoMapa': 'map',
  'iconoPerfil': 'person',
  'logoUrl': '',
  'iconoUrl': '',
  'fotoPortadaUrl': '',
};

/// Nombres de iconos Material que la app sabe dibujar.
const Set<String> iconosDeMenu = {
  'home',
  'search',
  'map',
  'person',
  'store',
  'restaurant',
  'shopping',
  'school',
  'campaign',
  'place',
  'favorite',
};

/// Secciones de publicidad (arriba y abajo) y anuncios por sección.
const int seccionesPublicidad = 2;

/// Imágenes que rota cada carrusel de publicidad.
const int anunciosPorSeccion = 3;

/// Completa [guardados] con los valores que todavía no están en la base.
Map<String, String> aparienciaVisible(Map<String, String> guardados) {
  return {
    for (final entrada in aparienciaPredeterminada.entries)
      entrada.key: guardados[entrada.key] ?? entrada.value,
  };
}
