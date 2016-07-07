<?xml version="1.0" encoding="utf-8"?>
<app:app xmlns:app="http://etl.dob.sk/app"  xmlns:etl="http://etl.dob.sk/etl">
<app:conf name="driver.http.agent">Mozilla/5.0 (Windows NT 6.1; WOW64; rv:5.0) Gecko/20100101 Firefox/5.0</app:conf>
<app:req>
	<etl xmlns="http://etl.dob.sk/etlp">
		<!-- embedded xsl -->
		<embed:embed id="google.xsl" xmlns:embed="http://etl.dob.sk/embed">
		<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
				xmlns:xhtml="http://www.w3.org/1999/xhtml"
				xmlns:etl="http://etl.dob.sk/etl"
				exclude-result-prefixes="xhtml">
		<xsl:output method="xml" indent="yes" encoding="utf-8"/>
		<xsl:template match="/">
		<result><xsl:text>
</xsl:text>
			<xsl:apply-templates select="//xhtml:h3[@class]/xhtml:a"/>
		</result>
		</xsl:template>

		<xsl:template match="xhtml:a"><xsl:apply-templates select="text()|*"/><xsl:value-of select="concat(' == ', @href)" disable-output-escaping="yes"/><xsl:text>
</xsl:text></xsl:template>
		</xsl:stylesheet>
		</embed:embed>

		<!-- database source -->
		<data name="google" action="print">	<!-- load -->
			<feed name="search" date="" enabled="1">	<!-- transform -->
				<source enabled="1" name="query" xsl="embed://google.xsl">	<!-- extract -->
					<http:req http:method="get" xmlns:http="http://etl.dob.sk/http">
						<http:url><![CDATA[http://8h.sk/s]]></http:url>
						<http:param name="q" app:inject="q">sk</http:param>
					</http:req>
				</source>
			<!-- params -->
			</feed>
		</data>
	</etl>
</app:req>
</app:app>
