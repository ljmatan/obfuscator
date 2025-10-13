import 'package:flutter/material.dart';

void main() {
  runApp(const G0c3N());
}

class G0c3N extends StatelessWidget {
  const G0c3N({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MbmFpSt5aN(s4Bjq: 'Flutter Demo Home Page'),
    );
  }
}

class MbmFpSt5aN extends StatefulWidget {
  const MbmFpSt5aN({super.key, required this.s4Bjq});

  final String s4Bjq;

  @override
  State<MbmFpSt5aN> createState() => _RuwFzsUE4kV9Qzy();
}

class _RuwFzsUE4kV9Qzy extends State<MbmFpSt5aN> {
  int _rScMqsf = 0;

  void _iMDxSMnA5kH8uxR9() {
    setState(() {
      _rScMqsf++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.s4Bjq),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_rScMqsf',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _iMDxSMnA5kH8uxR9,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
