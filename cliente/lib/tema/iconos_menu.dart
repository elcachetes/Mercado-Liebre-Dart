import 'package:flutter/material.dart';

/// Iconos que el administrador puede asignar a cada pestaña.
const Map<String, String> nombresDeIcono = {
  'home': 'Casa',
  'search': 'Buscar',
  'map': 'Mapa',
  'person': 'Persona',
  'store': 'Tienda',
  'restaurant': 'Comida',
  'shopping': 'Bolsa',
  'school': 'Escuela',
  'campaign': 'Aviso',
  'place': 'Lugar',
  'favorite': 'Favorito',
};

/// Dibuja el icono de menú. [activo] usa la variante rellena cuando existe.
IconData iconoMenu(String clave, {bool activo = false}) {
  switch (clave) {
    case 'search':
      return Icons.search;
    case 'map':
      return activo ? Icons.map : Icons.map_outlined;
    case 'person':
      return activo ? Icons.person : Icons.person_outline;
    case 'store':
      return activo ? Icons.storefront : Icons.storefront_outlined;
    case 'restaurant':
      return activo ? Icons.restaurant : Icons.restaurant_outlined;
    case 'shopping':
      return activo ? Icons.shopping_bag : Icons.shopping_bag_outlined;
    case 'school':
      return activo ? Icons.school : Icons.school_outlined;
    case 'campaign':
      return activo ? Icons.campaign : Icons.campaign_outlined;
    case 'place':
      return activo ? Icons.place : Icons.place_outlined;
    case 'favorite':
      return activo ? Icons.favorite : Icons.favorite_border;
    default:
      return activo ? Icons.home : Icons.home_outlined;
  }
}
