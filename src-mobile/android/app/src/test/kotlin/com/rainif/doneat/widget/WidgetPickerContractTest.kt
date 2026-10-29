package com.rainif.doneat.widget

import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import org.junit.Assert.*
import org.junit.Test
import org.w3c.dom.Element

class WidgetPickerContractTest {
    private val android = "http://schemas.android.com/apk/res/android"
    private fun source(path: String): File = sequenceOf(File("src/main/$path"), File("app/src/main/$path"))
        .first { it.exists() }
    private fun xml(file: File) = DocumentBuilderFactory.newInstance().apply {
        isNamespaceAware = true
        setFeature("http://apache.org/xml/features/disallow-doctype-decl", true)
    }.newDocumentBuilder().parse(file)

    @Test fun `every suite kind has a distinct preserved picker receiver and valid provider sizes`() {
        val manifest = xml(source("AndroidManifest.xml"))
        val receivers = manifest.getElementsByTagName("receiver")
        val names = mutableSetOf<String>()
        for (kind in DoneAtWidgetKind.entries) {
            val name = ".widget." + kind.receiver.simpleName
            assertTrue("duplicate receiver $name", names.add(name))
            val receiver = (0 until receivers.length).map { receivers.item(it) as Element }
                .firstOrNull { it.getAttributeNS(android, "name") == name }
            assertNotNull("missing $name", receiver)
            val meta = receiver!!.getElementsByTagName("meta-data").item(0) as Element
            val resource = meta.getAttributeNS(android, "resource").removePrefix("@xml/")
            for (version in listOf("xml", "xml-v31")) {
                val provider = xml(source("res/$version/$resource.xml")).documentElement
                assertEquals("0", provider.getAttributeNS(android, "updatePeriodMillis"))
                assertEquals("home_screen", provider.getAttributeNS(android, "widgetCategory"))
                assertTrue(provider.getAttributeNS(android, "minWidth").removeSuffix("dp").toInt() > 0)
                assertTrue(provider.getAttributeNS(android, "minHeight").removeSuffix("dp").toInt() > 0)
            }
        }
        for (legacy in listOf("DoneAtWidgetReceiver", "DoneAtWidgetMediumReceiver", "DoneAtWidgetLargeReceiver")) {
            assertTrue((0 until receivers.length).any { (receivers.item(it) as Element).getAttributeNS(android, "name") == ".widget.$legacy" })
        }
    }
}
