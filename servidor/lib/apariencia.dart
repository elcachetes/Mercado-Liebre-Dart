/// Claves que el administrador puede cambiar, con su valor inicial.
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
  // Espacios publicitarios de la barra lateral (arriba y abajo).
  // Imagen vacía muestra "Anúnciate aquí"; enlace vacío no abre nada.
  'publicidad1Url': '',
  'publicidad1Enlace': '',
  'publicidad2Url': '',
  'publicidad2Enlace': '',
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

/// Completa [guardados] con los valores que todavía no están en la base.
Map<String, String> aparienciaVisible(Map<String, String> guardados) {
  return {
    for (final entrada in aparienciaPredeterminada.entries)
      entrada.key: guardados[entrada.key] ?? entrada.value,
  };
}
