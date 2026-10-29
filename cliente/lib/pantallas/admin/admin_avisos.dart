import 'package:flutter/material.dart';

import '../../modelos/modelos.dart';
import '../../servicios/estado.dart';
import '../../tema/tema_liebre.dart';
import '../../widgets/comunes.dart';
import 'comun_admin.dart';

/// Avisos institucionales de Inicio: crear, editar, ocultar y borrar.
class AdminAvisos extends StatelessWidget {
  /// Sesión de administrador.
  const AdminAvisos({super.key, required this.estado});

  /// Sesión de administrador.
  final EstadoApp estado;

  Future<void> _editar(BuildContext context, Future<void> Function() recargar, [Aviso? aviso]) async {
    if (await showDialog<bool>(context: context, builder: (_) => _EditarAviso(estado: estado, aviso: aviso)) == true) {
      await recargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = estado.api;
    return CargaAdmin<List<Aviso>>(
      cargar: api.avisosAdmin,
      construir: (context, avisos, recargar) {
        final esquema = Theme.of(context).colorScheme;
        return [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Los avisos activos aparecen en Inicio para todas las personas.',
                  style: TextStyle(color: esquema.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: Espacio.s),
              FilledButton.icon(
                onPressed: () => _editar(context, recargar),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo aviso'),
              ),
            ],
          ),
          const SizedBox(height: Espacio.m),
          if (avisos.isEmpty) const EstadoVacio(icono: Icons.campaign_outlined, mensaje: 'Todavía no hay avisos.'),
          for (final aviso in avisos)
            Card(
              child: ListTile(
                title: Text(aviso.titulo),
                subtitle: Text(
                  '${aviso.contenido}\n${fechaCorta(aviso.publicadoEn)}',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                onTap: () => _editar(context, recargar, aviso),
                trailing: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Tooltip(
                      message: aviso.activo ? 'Visible en Inicio' : 'Oculto',
                      child: Switch(
                        value: aviso.activo,
                        onChanged: (activo) async {
                          if (await intentar(
                            context,
                            () => api.guardarAviso(id: aviso.id, titulo: aviso.titulo, contenido: aviso.contenido, activo: activo),
                          )) {
                            await recargar();
                          }
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Eliminar',
                      icon: Icon(Icons.delete_outline, color: esquema.error),
                      onPressed: () async {
                        if (!await confirmar(context, titulo: 'Eliminar aviso', mensaje: '"${aviso.titulo}" se borrará.')) {
                          return;
                        }
                        if (context.mounted &&
                            await intentar(context, () => api.eliminarAviso(aviso.id), exito: 'Aviso eliminado.')) {
                          await recargar();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
        ];
      },
    );
  }
}

/// Alta ([aviso] null) o edición. Devuelve true si guardó.
class _EditarAviso extends StatefulWidget {
  const _EditarAviso({required this.estado, this.aviso});

  final EstadoApp estado;
  final Aviso? aviso;

  @override
  State<_EditarAviso> createState() => _EditarAvisoState();
}

class _EditarAvisoState extends State<_EditarAviso> {
  final _formulario = GlobalKey<FormState>();
  late final _titulo = TextEditingController(text: widget.aviso?.titulo);
  late final _contenido = TextEditingController(text: widget.aviso?.contenido);
  late bool _activo = widget.aviso?.activo ?? true;
  bool _ocupado = false;

  @override
  void dispose() {
    _titulo.dispose();
    _contenido.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!(_formulario.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _ocupado = true);
    final ok = await intentar(
      context,
      () => widget.estado.api.guardarAviso(
        id: widget.aviso?.id,
        titulo: _titulo.text.trim(),
        contenido: _contenido.text.trim(),
        activo: _activo,
      ),
      exito: widget.aviso == null ? 'Aviso publicado.' : 'Aviso guardado.',
    );
    if (!mounted) {
      return;
    }
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? requerido(String? valor) => (valor ?? '').trim().isEmpty ? 'Campo obligatorio' : null;
    return AlertDialog(
      title: Text(widget.aviso == null ? 'Nuevo aviso' : 'Editar aviso'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formulario,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _titulo,
                  maxLength: 120,
                  decoration: const InputDecoration(labelText: 'Título'),
                  validator: requerido,
                ),
                TextFormField(
                  controller: _contenido,
                  maxLength: 2000,
                  minLines: 3,
                  maxLines: 8,
                  decoration: const InputDecoration(labelText: 'Texto del aviso'),
                  validator: requerido,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _activo,
                  title: const Text('Mostrar en Inicio'),
                  onChanged: (valor) => setState(() => _activo = valor),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _ocupado ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _ocupado ? null : _guardar, child: const Text('Guardar')),
      ],
    );
  }
}
