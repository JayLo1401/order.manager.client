import 'package:flutter_test/flutter_test.dart';
import 'package:order_manager_client/order/order_poller.dart';
import 'package:order_manager_client/order/order_service.dart';

ReadyItem _item(String key, {String guest = '', int? number}) => ReadyItem(
      key: key,
      number: number,
      guest: guest,
      itemName: 'Suppe',
      itemIcon: '🥣',
      options: '',
      ageSeconds: 0,
    );

void main() {
  test('ReadyItem liest die API-Felder und ruft Gast oder Nummer auf', () {
    final item = ReadyItem.fromJson({
      'key': '42-1760551200',
      'number': 7,
      'guest': ' Anna ',
      'item_name': 'Kürbiscremesuppe',
      'item_icon': '🎃',
      'options': '',
      'age_seconds': 4,
    });
    expect(item.key, '42-1760551200');
    expect(item.who, 'Anna');
    expect(item.ageSeconds, 4);
    expect(_item('x', number: 3).who, 'Nr. 3');
  });

  test('neue Meldungen werden an eine offene Anzeige angehaengt, Gong je Schwung', () {
    var chimes = 0;
    final poller = OrderPoller(onAnnounce: (_) => chimes++);
    addTearDown(poller.dispose);

    poller.announce([_item('a'), _item('b')]);
    poller.announce([_item('c')]);
    expect(poller.pickup!.map((i) => i.key), ['a', 'b', 'c']);
    expect(chimes, 2);

    poller.dismiss();
    expect(poller.pickup, isNull);
  });
}
