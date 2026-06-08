# 🚗 Car Fuel GPS - App de Multimídia para Carro

Aplicativo Flutter 100% offline para cálculo de autonomia de combustível com rastreamento GPS.

## 📱 Funcionalidades

- **Abastecimento**: Cadastra litros, consumo do veículo e quilometragem inicial
- **Cálculo automático**: Calcula autonomia total (litros ÷ consumo por km)
- **GPS em tempo real**: Rastreia distância percorrida automaticamente via GPS
- **Atualização manual**: Permite inserir nova quilometragem manualmente
- **Histórico completo**: Salva todas as viagens no banco SQLite local
- **Interface multimídia**: Design escuro otimizado para uso no carro

## 🚀 Como rodar

```bash
cd car_fuel_gps
flutter pub get
flutter run
```

## 📂 Estrutura do Projeto

```
lib/
├── main.dart                 # Entry point + tema dark
├── models/
│   └── trip_model.dart       # Modelo de dados da viagem
├── screens/
│   ├── home_screen.dart      # Painel principal com gauge
│   ├── add_fuel_screen.dart  # Tela de abastecimento
│   └── history_screen.dart   # Histórico de viagens
├── services/
│   ├── database_service.dart # SQLite offline
│   └── gps_service.dart      # Rastreamento GPS
├── providers/
│   └── app_provider.dart     # State management
└── widgets/
    ├── fuel_gauge.dart       # Medidor circular de combustível
    └── trip_card.dart        # Card de viagem no histórico
```

## 🔧 Configuração Android

Copie o arquivo `android_manifest.xml` para:
```
android/app/src/main/AndroidManifest.xml
```

Isso garante as permissões de GPS necessárias para funcionamento offline.

## 📝 Como usar

1. Toque em **+** para novo abastecimento
2. Informe: litros, consumo (L/km) e KM atual do painel
3. O app calcula automaticamente a autonomia
4. Toque em **INICIAR GPS** para rastrear automaticamente
5. Ou use **Atualização Manual** para inserir KM do painel
6. Toque em **FINALIZAR VIAGEM** quando terminar

## ⚡ Funciona 100% Offline

- Banco de dados SQLite local
- GPS nativo do dispositivo (não precisa de internet)
- Sem APIs externas ou serviços em nuvem
