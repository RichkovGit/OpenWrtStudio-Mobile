import 'package:flutter/material.dart';
import 'package:luci_mobile/models/forkop_node.dart';

class ForkopQuickChoices extends StatelessWidget {
  final List<ForkopNode> nodes;
  final bool busy;
  final ValueChanged<String> onSelect;
  const ForkopQuickChoices({super.key,required this.nodes,required this.onSelect,this.busy=false});
  @override
  Widget build(BuildContext context) => Wrap(
    spacing:6,runSpacing:6,
    children:nodes.map((node)=>ChoiceChip(
      key:ValueKey('vpn-${node.name}'),
      selected:node.isActive,
      selectedColor:const Color(0xFF00D2FF).withValues(alpha:0.25),
      label:Text(node.displayTitle,style:TextStyle(color:node.isActive?const Color(0xFF00D2FF):Colors.white,fontSize:11)),
      onSelected:busy||!node.hasLiveState||node.group.isEmpty?null:(selected){if(selected) onSelect(node.name);},
    )).toList(),
  );
}
