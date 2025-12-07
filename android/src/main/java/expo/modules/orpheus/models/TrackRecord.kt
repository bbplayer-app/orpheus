package expo.modules.orpheus.models

import expo.modules.kotlin.records.Field
import expo.modules.kotlin.records.Record

class LoudnessRecord : Record {
    @Field
    var measured_i: Double = 0.0

    @Field
    var target_i: Double = 0.0
}

class TrackRecord : Record {
    @Field
    var id: String = ""

    @Field
    var url: String = ""

    @Field
    var title: String? = null

    @Field
    var artist: String? = null

    @Field
    var artwork: String? = null

    // unit: second
    @Field
    var duration: Double? = null

    @Field
    var loudness: LoudnessRecord? = null
}