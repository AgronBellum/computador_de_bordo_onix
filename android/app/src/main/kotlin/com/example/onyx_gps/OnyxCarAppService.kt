package com.example.onyx_gps

import android.content.Intent
import androidx.car.app.CarAppService
import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.car.app.model.Action
import androidx.car.app.model.Pane
import androidx.car.app.model.PaneTemplate
import androidx.car.app.model.Row
import androidx.car.app.model.Template
import androidx.car.app.validation.HostValidator

class OnyxCarAppService : CarAppService() {
    override fun createHostValidator(): HostValidator {
        return HostValidator.ALLOW_ALL_HOSTS_VALIDATOR
    }

    override fun onCreateSession(): Session {
        return OnyxCarSession()
    }
}

class OnyxCarSession : Session() {
    override fun onCreateScreen(intent: Intent): Screen {
        return OnyxCarScreen(carContext)
    }
}

class OnyxCarScreen(carContext: CarContext) : Screen(carContext) {
    override fun onGetTemplate(): Template {
        val pane = Pane.Builder()
            .addRow(
                Row.Builder()
                    .setTitle("Computador de Bordo Onix")
                    .addText("Assistente, rotas e dados do veículo ativos no aparelho.")
                    .build(),
            )
            .addRow(
                Row.Builder()
                    .setTitle("Android Auto preparado")
                    .addText("Use comandos de voz e acompanhe pelo app principal.")
                    .build(),
            )
            .build()

        return PaneTemplate.Builder(pane)
            .setHeaderAction(Action.APP_ICON)
            .setTitle("Onix")
            .build()
    }
}