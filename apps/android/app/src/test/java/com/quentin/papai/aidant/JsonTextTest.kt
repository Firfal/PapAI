package com.quentin.papai.aidant

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class JsonTextTest {
    @Test fun missingAndJsonNullAreAbsent() {
        val json = JSONObject("""{"senior":null,"name":null}""")
        assertEquals("", json.text("senior"))
        assertEquals("", json.text("name"))
        assertEquals("", json.text("missing"))
    }

    @Test fun literalNullAndStoredNullAreAbsent() {
        for (value in listOf(null, "", "null", " NULL ", "  ")) {
            assertEquals("", cleanText(value))
        }
        assertEquals("", JSONObject().put("senior", "null").text("senior"))
    }

    @Test fun namesAreTrimmedAndPreserved() {
        assertEquals("Marie", JSONObject().put("name", " Marie ").text("name"))
        assertEquals("Jean", cleanText(" Jean "))
    }

    @Test fun invalidTypesAreAbsent() {
        for (value in listOf(42, true, JSONObject(), JSONArray())) {
            assertEquals("", JSONObject().put("name", value).text("name"))
        }
    }

    @Test fun arrayNullsAreAbsent() {
        val array = JSONArray("""[null,"null"," Marie ",42]""")
        assertEquals("", array.text(0))
        assertEquals("", array.text(1))
        assertEquals("Marie", array.text(2))
        assertEquals("", array.text(3))
        assertEquals("", array.text(4))
    }
}
