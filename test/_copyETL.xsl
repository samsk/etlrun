<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
				xmlns:etl="http://etl.dob.sk/etl">
<xsl:output method="xml" indent="yes" encoding="utf-8"/>

<xsl:template match="/">
<copy>
<xsl:apply-templates select="*"/>
</copy>
</xsl:template>

<!-- copy without envelope -->
<xsl:template match="etl:data">
<xsl:copy-of select="child::*"/>
</xsl:template>

<xsl:template match="etl:err">
<xsl:copy-of select="."/>
</xsl:template>

<xsl:template match="*">
<xsl:copy-of select="."/>
</xsl:template>

</xsl:stylesheet>
