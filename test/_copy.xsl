<?xml version="1.0" encoding="utf-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
				xmlns:etl="http://etl.dob.sk/etl">
<xsl:output method="xml" indent="yes" encoding="utf-8"/>

<xsl:template match="/">
<xsl:apply-templates select="*"/>
<xsl:comment>processed by _copy.xsl</xsl:comment>
</xsl:template>

<xsl:template match="*">
<xsl:copy-of select="."/>
</xsl:template>

</xsl:stylesheet>
